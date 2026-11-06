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
                  ["dmg", "zip", "pkg"].contains(url.pathExtension.lowercased()) else { return nil }
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
                (url.lastPathComponent.lowercased().contains("universal") ? 0 : 10) + (["dmg": 0, "zip": 1, "pkg": 2][url.pathExtension.lowercased()] ?? 3)
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
    }
    @Published private(set) var state: State = .idle
    let currentVersion: String
    private let service: ReleaseService
    init(currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0", service: ReleaseService = ReleaseService()) {
        self.currentVersion = currentVersion
        self.service = service
    }
    func check() async {
        guard state != .checking else { return }
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
    @State private var openFailed = false
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(text("检查更新", "Check for Updates")) {
                    openFailed = false
                    Task { await checker.check() }
                }
                .disabled(checker.state == .checking)
                if checker.state == .checking { ProgressView().controlSize(.small) }
                if case .available(let release) = checker.state {
                    Spacer()
                    Button(release.download == nil ? text("查看发布页面", "View Release") : text("下载更新", "Download Update")) {
                        openFailed = !NSWorkspace.shared.open(release.download ?? release.page)
                    }
                }
            }
            if let status {
                Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if openFailed { Text(text("无法打开下载链接，请重试。", "Unable to open the download link. Please try again.")).foregroundStyle(.red) }
        }
        .font(.system(size: 14))
    }
    private var status: String? {
        switch checker.state {
        case .idle: return nil
        case .checking: return text("正在检查更新…", "Checking for updates…")
        case .noRelease: return text("尚无发布版本", "No releases available yet")
        case .current: return text("已是最新版本", "You’re up to date")
        case .available(let release): return text("发现新版本 ", "New version available: ") + release.tag
        case .failed: return text("检查更新失败，请稍后重试。", "Unable to check for updates. Please try again later.")
        }
    }
}
