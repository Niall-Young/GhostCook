import Foundation

// launchd owns the one-shot startup job, so the daemon outlives GhostCook.
// No LaunchAgent is installed, and the job does not enable launch at login.
enum AilyService {
    static var executable: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aily-cli/bin/aily-cli").path }
    static var installed: Bool { FileManager.default.isExecutableFile(atPath: executable) }
    static var environment: [String: String] {
        var values = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AILY_CLI_") }
        values["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (values["PATH"] ?? "")
        return values
    }
    static func status() -> Bool? {
        guard installed, let text = try? Command.run(executable, ["daemon", "status", "--json"], timeout: 5, environment: environment, acceptedExitCodes: [0, 3]) else { return nil }
        return parseStatus(text)
    }
    static func parseStatus(_ text: String) -> Bool? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end,
              let data = String(text[start...end]).data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if (json["error"] as? [String: Any])?["code"] as? String == "DAEMON_UNREACHABLE" { return false }
        if json["ok"] as? Bool == true { return (json["data"] as? [String: Any])?["running"] as? Bool ?? true }
        return json["running"] as? Bool ?? (json["daemon"] as? [String: Any])?["running"] as? Bool ?? (json["data"] as? [String: Any])?["running"] as? Bool
    }
    static func set(_ enabled: Bool) throws {
        guard installed else { throw OperationError("未安装飞书 aily CLI / Feishu aily CLI is not installed") }
        if !enabled {
            _ = try Command.run(executable, ["daemon", "stop", "--yes", "--timeout", "15"], timeout: 25, environment: environment, acceptedExitCodes: [0, 3])
            if status() == true { throw OperationError("aily 服务仍在运行 / aily is still running") }
            return
        }
        if status() == true { return }
        let label = "dev.nialyoung.onecook.aily-start." + UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(label)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "gui/\(getuid())"
        let definition: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/env", "-i"] + environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + [executable, "daemon", "start"],
            "RunAtLoad": true, "KeepAlive": false, "AbandonProcessGroup": true,
            "ExitTimeOut": 1, "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"
        ]
        let url = directory.appendingPathComponent("job.plist")
        try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        defer { _ = try? Command.run("/bin/launchctl", ["bootout", domain + "/" + label], timeout: 3) }
        _ = try Command.run("/bin/launchctl", ["bootstrap", domain, url.path], timeout: 5)
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if status() == true { return }
            Thread.sleep(forTimeInterval: 1)
        }
        throw OperationError("aily 启动超时，请检查服务日志 / aily startup timed out; check its logs")
    }
}
