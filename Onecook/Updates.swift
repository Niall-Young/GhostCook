import Foundation
import SwiftUI
import AppKit

// Public release pages only: no GitHub REST/GraphQL API or credentials.
struct ReleaseVersion: Comparable, Equatable {
    let components: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") || value.hasPrefix("V") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! } + Array(repeating: 0, count: 4 - parts.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

struct AvailableRelease: Equatable {
    let tag: String
    let page: URL
    let download: URL?
}

enum ReleaseCheckError: Error {
    case http(Int), invalidPage, invalidVersion
}

struct ReleaseService {
    static let repository = URL(string: "https://github.com/Niall-Young/GhostCook")!
    typealias Fetch = (URL) async throws -> (Data, HTTPURLResponse)
    var fetch: Fetch = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReleaseCheckError.invalidPage }
        return (data, response)
    }

    func latest(currentVersion: String) async throws -> AvailableRelease? {
        let (data, response) = try await fetch(Self.repository.appendingPathComponent("releases/latest"))
        guard response.statusCode == 200 else { throw ReleaseCheckError.http(response.statusCode) }
        guard let page = response.url, page.scheme == "https", page.host == "github.com" else { throw ReleaseCheckError.invalidPage }
        let prefix = Self.repository.path + "/releases/tag/"
        guard page.path.hasPrefix(prefix) else {
            // GitHub redirects /latest to /releases for an empty repository.
            if page.path == Self.repository.path + "/releases",
               String(decoding: data, as: UTF8.self).contains("There aren’t any releases here") { return nil }
            throw ReleaseCheckError.invalidPage
        }
        let tag = String(page.path.dropFirst(prefix.count))
        guard let remote = ReleaseVersion(tag), let local = ReleaseVersion(currentVersion) else { throw ReleaseCheckError.invalidVersion }
        guard remote > local else { return AvailableRelease(tag: tag, page: page, download: nil) }
        let assetsURL = Self.repository.appendingPathComponent("releases/expanded_assets").appendingPathComponent(tag)
        let (assets, assetsResponse) = try await fetch(assetsURL)
        guard assetsResponse.statusCode == 200 else { throw ReleaseCheckError.http(assetsResponse.statusCode) }
        return AvailableRelease(tag: tag, page: page, download: Self.downloadURL(html: String(decoding: assets, as: UTF8.self), tag: tag))
    }

    static func downloadURL(html: String, tag: String, architecture: String = machineArchitecture) -> URL? {
        let regex = try! NSRegularExpression(pattern: #"href\s*=\s*["']([^"']+)["']"#)
        let prefix = repository.path + "/releases/download/" + tag + "/"
        let candidates = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match -> URL? in
            guard let range = Range(match.range(at: 1), in: html),
                  let url = URL(string: String(html[range]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: repository)?.absoluteURL,
                  url.scheme == "https", url.host == "github.com", url.path.hasPrefix(prefix),
                  ["dmg", "zip"].contains(url.pathExtension.lowercased()) else { return nil }
            let name = url.lastPathComponent.lowercased()
            guard !name.contains("windows"), !name.contains("linux") else { return nil }
            let arm = name.contains("arm64") || name.contains("aarch64") || name.contains("apple-silicon")
            let intel = name.contains("x86_64") || name.contains("amd64") || name.contains("intel") || name.contains("x64")
            let universal = name.contains("universal")
            guard universal || (architecture == "arm64" ? !intel : !arm) else { return nil }
            return url
        }
        return candidates.sorted {
            func priority(_ url: URL) -> Int {
                (url.lastPathComponent.lowercased().contains("universal") ? 0 : 10) + (["zip": 0, "dmg": 1][url.pathExtension.lowercased()] ?? 3)
            }
            return priority($0) < priority($1)
        }.first
    }

    static var machineArchitecture: String {
        // Hardware detection also works when an Intel build runs through Rosetta.
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1 ? "arm64" : "x86_64"
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle, checking, noRelease, current, available(AvailableRelease), failed
        case downloading, installing, installFailed(String)
    }
    @Published private(set) var state: State = .idle
    let currentVersion: String
    private let service: ReleaseService
    private var installationMonitor: Timer?
    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0", service: ReleaseService = ReleaseService()) {
        self.currentVersion = currentVersion
        self.service = service
    }
    func recoverFailure() {
        guard state == .idle, let failure = try? String(contentsOf: UpdateInstaller.failureURL, encoding: .utf8) else { return }
        state = .installFailed(failure)
        try? FileManager.default.removeItem(at: UpdateInstaller.failureURL)
    }
    var busy: Bool { state == .checking || state == .downloading || state == .installing }
    // AppKit's termination loop must be able to receive failure reports even
    // while the update task is still on the main dispatch queue's stack.
    func monitorInstallation(_ helper: Process, failure: URL = UpdateInstaller.failureURL,
                             cancelTermination: @escaping () -> Void = {
                                 (NSApp.delegate as? AppDelegate)?.cancelUpdateTermination()
                             }) {
        installationMonitor?.invalidate()
        state = .installing
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard !helper.isRunning else { return }
            timer.invalidate()
            self.installationMonitor = nil
            let message = (try? String(contentsOf: failure, encoding: .utf8))
                ?? "更新未完成，请重试 / Update did not complete; please retry"
            try? FileManager.default.removeItem(at: failure)
            // The helper has stopped, so cancelling termination cannot race
            // with a later replacement of the running application.
            self.state = .installFailed(message)
            cancelTermination()
        }
        installationMonitor = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func install() async {
        guard case .available(let release) = state else { return }
        state = .downloading
        do {
            let prepared = try await Task.detached { try await UpdateInstaller.prepare(release) }.value
            do { monitorInstallation(try UpdateInstaller.launchHelper(prepared)) }
            catch {
                try? FileManager.default.removeItem(at: prepared.directory)
                throw error
            }
            NSApplication.shared.terminate(nil)
        } catch {
            state = .installFailed(error.localizedDescription)
        }
    }
    func check() async {
        guard !busy else { return }
        state = .checking
        do {
            guard let release = try await service.latest(currentVersion: currentVersion) else { state = .noRelease; return }
            state = ReleaseVersion(release.tag)! > ReleaseVersion(currentVersion)! ? .available(release) : .current
        } catch {
            NSLog("GhostCook update check: %@", String(describing: error))
            state = .failed
        }
    }
}

struct UpdatePreferencesView: View {
    let english: Bool
    @StateObject private var checker = UpdateChecker()
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(text("检查更新", "Check for Updates")) {
                    Task { await checker.check() }
                }
                .disabled(checker.busy)
                if checker.busy { ProgressView().controlSize(.small) }
                if case .available(let release) = checker.state {
                    Spacer()
                    Button(text("更新并重新启动", "Update and Restart")) {
                        Task { await checker.install() }
                    }
                    .disabled(release.download == nil)
                }
            }
            if let status {
                Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

        }
        .font(.system(size: 14))
        .onAppear { checker.recoverFailure() }
    }
    private var status: String? {
        switch checker.state {
        case .idle: return nil
        case .checking: return text("正在检查更新…", "Checking for updates…")
        case .noRelease: return text("尚无发布版本", "No releases available yet")
        case .current: return text("已是最新版本", "You’re up to date")
        case .available(let release):
            return release.download == nil
                ? text("此版本没有适用于当前 Mac 的更新包", "No compatible update archive for this Mac")
                : text("发现新版本 ", "New version available: ") + release.tag
        case .downloading: return text("正在下载并验证更新…", "Downloading and verifying update…")
        case .installing: return text("正在安装，即将重新启动…", "Installing; restarting shortly…")
        case .installFailed(let message): return text("更新失败：", "Update failed: ") + message
        case .failed: return text("检查更新失败，请稍后重试。", "Unable to check for updates. Please try again later.")
        }
    }
}
