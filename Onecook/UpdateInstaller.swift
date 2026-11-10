import AppKit
import Foundation

struct UpdateInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// All downloads and preparation finish before the running application is touched.
struct UpdateInstaller {
    static let signingRequirement = #"anchor apple generic and identifier "dev.nialyoung.onecook" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "V8GVW783CK""#
    static var failureURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GhostCook/UpdateFailure.txt")
    }

    struct Prepared {
        let directory: URL
        let app: URL
        let target: URL
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError(message: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func validate(_ app: URL, release: AvailableRelease) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "dev.nialyoung.onecook",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let expected = ReleaseVersion(release.tag), ReleaseVersion(version) == expected,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateInstallError(message: "安装包中的应用或版本不匹配 / Invalid app or version in update")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + signingRequirement, app.path])
        try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    static func prepare(_ release: AvailableRelease, target: URL = Bundle.main.bundleURL) async throws -> Prepared {
        let fm = FileManager.default
        let target = target.resolvingSymlinksInPath()
        guard target.pathExtension == "app", !target.path.hasPrefix("/Volumes/"),
              !target.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateInstallError(message: "请先将 GhostCook 移到可写入的应用程序文件夹，再重试更新 / Move GhostCook to a writable Applications folder and retry")
        }
        guard let download = release.download, ["zip", "dmg"].contains(download.pathExtension.lowercased()) else {
            throw UpdateInstallError(message: "此版本缺少可自动安装的更新包 / This release has no compatible update archive")
        }
        let directory = target.deletingLastPathComponent().appendingPathComponent(".GhostCook-update-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            var request = URLRequest(url: download)
            request.timeoutInterval = 60
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let (temporary, response) = try await session.download(for: request)
            defer { try? fm.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https" else {
                throw UpdateInstallError(message: "下载更新失败 / Update download failed")
            }
            let archive = directory.appendingPathComponent("Update." + download.pathExtension.lowercased())
            try fm.moveItem(at: temporary, to: archive)
            let extracted = directory.appendingPathComponent("Extracted")
            try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
            if archive.pathExtension == "zip" {
                try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            } else {
                let mount = directory.appendingPathComponent("Mounted")
                try fm.createDirectory(at: mount, withIntermediateDirectories: false)
                try run("/usr/bin/hdiutil", ["attach", archive.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
                defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
                let apps = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
                guard apps.count == 1 else { throw UpdateInstallError(message: "无效的磁盘映像 / Invalid update disk image") }
                try run("/usr/bin/ditto", [apps[0].path, extracted.appendingPathComponent("GhostCook.app").path])
            }
            let apps = try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
            guard apps.count == 1 else { throw UpdateInstallError(message: "更新包中未找到唯一应用 / Update must contain one app") }
            try validate(apps[0], release: release)
            return Prepared(directory: directory, app: apps[0], target: target)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    // Positional arguments keep spaces, quotes and shell metacharacters in paths inert.
    // The old app stays in the same filesystem until replacement and launch succeed.
    static let helperScript = #"""
    #!/bin/sh
    target=$1
    staged=$2
    work=$3
    parent_pid=$4
    failure=$5
    launcher=$6
    backup="$work/Previous.app"
    count=0
    while kill -0 "$parent_pid" 2>/dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 120 ]; then
            echo '应用未能退出，更新已取消 / App did not quit; update cancelled' > "$failure"
            exit 1
        fi
        sleep 1
    done
    if ! /bin/mv "$target" "$backup"; then
        echo '无法替换原应用 / Could not move the installed app' > "$failure"
        "$launcher" "$target"
        exit 1
    fi
    if ! /bin/mv "$staged" "$target"; then
        /bin/mv "$backup" "$target"
        echo '安装失败，已恢复原版本 / Installation failed; previous version restored' > "$failure"
        "$launcher" "$target"
        exit 1
    fi
    if ! "$launcher" "$target"; then
        /bin/mv "$target" "$work/Failed.app"
        /bin/mv "$backup" "$target"
        echo '新版无法启动，已恢复原版本 / Could not launch update; previous version restored' > "$failure"
        "$launcher" "$target"
        exit 1
    fi
    /bin/rm -rf "$work"
    """#

    static func launchHelper(_ prepared: Prepared, parentPID: Int32 = ProcessInfo.processInfo.processIdentifier,
                             failure: URL = failureURL) throws {
        try FileManager.default.createDirectory(at: failure.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: failure)
        let script = prepared.directory.appendingPathComponent("install.sh")
        try helperScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, prepared.target.path, prepared.app.path, prepared.directory.path, String(parentPID), failure.path, "/usr/bin/open"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
