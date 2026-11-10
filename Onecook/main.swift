import AppKit

let application = NSApplication.shared
// Exercise AppKit's real termination loop in a separate, isolated test process.
#if DEBUG
final class UpdateShutdownProbe: NSObject, NSApplicationDelegate {
    private let suite = "dev.nialyoung.onecook.tests.shutdown." + UUID().uuidString
    private var store: ControlStore!
    private var checker: UpdateChecker?
    private var cancelledFirstAttempt = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = ControlStore(settings: Settings(defaults: UserDefaults(suiteName: suite)!))
        if ProcessInfo.processInfo.arguments.contains("--test-update-shutdown-failure") {
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/usr/bin/false")
            do { try helper.run() } catch { exit(2) }
            checker = UpdateChecker()
            checker?.monitorInstallation(helper, failure: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) {
                self.cancelledFirstAttempt = true
                NSApp.reply(toApplicationShouldTerminate: false)
                RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
            }
        }
        Task { @MainActor in NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if checker != nil && !cancelledFirstAttempt { return .terminateLater }
        store.shutdown {
            UserDefaults(suiteName: self.suite)?.removePersistentDomain(forName: self.suite)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
let delegate: NSApplicationDelegate = ProcessInfo.processInfo.arguments.contains(where: {
    ["--test-update-shutdown", "--test-update-shutdown-failure"].contains($0)
})
    ? UpdateShutdownProbe() : AppDelegate()
#else
let delegate = AppDelegate()
#endif
application.delegate = delegate
application.run()
