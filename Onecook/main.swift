import AppKit

let application = NSApplication.shared
// Exercise AppKit's real termination loop in a separate, isolated test process.
#if DEBUG
final class UpdateShutdownProbe: NSObject, NSApplicationDelegate {
    private let suite = "dev.nialyoung.onecook.tests.shutdown." + UUID().uuidString
    private var store: ControlStore!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = ControlStore(settings: Settings(defaults: UserDefaults(suiteName: suite)!))
        Task { @MainActor in NSApp.terminate(nil) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.shutdown {
            UserDefaults(suiteName: self.suite)?.removePersistentDomain(forName: self.suite)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
let delegate: NSApplicationDelegate = ProcessInfo.processInfo.arguments.contains("--test-update-shutdown")
    ? UpdateShutdownProbe() : AppDelegate()
#else
let delegate = AppDelegate()
#endif
application.delegate = delegate
application.run()
