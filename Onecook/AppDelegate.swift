import AppKit
import ApplicationServices

// A single switch silhouette, shared by the menu bar and the app's brand mark.
enum Brand {
    static func icon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let capsule = NSRect(x: rect.width * 0.06, y: rect.height * 0.25, width: rect.width * 0.88, height: rect.height * 0.5)
            NSColor.labelColor.setStroke()
            let outline = NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2)
            outline.lineWidth = max(1.3, size * 0.055); outline.stroke()
            NSColor.labelColor.setFill()
            let diameter = capsule.height * 0.66
            NSBezierPath(ovalIn: NSRect(x: capsule.maxX - diameter - capsule.height * 0.17, y: capsule.midY - diameter / 2, width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = Settings()
    lazy var store = ControlStore(settings: settings)
    private var statusItem: NSStatusItem!
    private var panel: ControlsPanel!
    private var controls: ControlsViewController!
    private var preferences: PreferencesController?
    private var guide: NSWindow?
    private var guideTimer: Timer?
    private var shortcuts: ShortcutManager!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var refreshTimer: Timer?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        if let button = statusItem.button {
            button.image = Brand.icon(size: 18); button.target = self; button.action = #selector(togglePanel); button.toolTip = "Onecook"; button.setAccessibilityLabel("Onecook")
        }
        controls = ControlsViewController(store: store)
        controls.onSettings = { [weak self] in self?.showPreferences($0) }
        controls.onQuit = { NSApp.terminate(nil) }
        controls.onResize = { [weak self] in if self?.panel?.isVisible == true { self?.positionPanel() } }
        panel = ControlsPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: controls.desiredHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = controls; panel.delegate = self
        store.onError = { [weak self] control, error in
            guard let self else { return }
            self.hidePanel()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(); alert.messageText = self.settings.english ? control.en : control.zh
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: self.settings.text("好", "OK"))
            if !AXIsProcessTrusted() { alert.addButton(withTitle: self.settings.text("辅助功能设置", "Accessibility Settings")) }
            if alert.runModal() == .alertSecondButtonReturn { SystemSettings.requestAccessibility() }
        }
        store.onBeforeExternalUI = { [weak self] in self?.hidePanel() }
        shortcuts = ShortcutManager()
        shortcuts.onTrigger = { [weak self] id in
            guard let self, let control = Control.all.first(where: { $0.id == id }) else { return }
            self.store.previousApp = NSWorkspace.shared.frontmostApplication
            if control.isTimed && !self.store.state(id).enabled || id == "resolution" || control.needsConfirmation {
                self.showPanel(); self.controls.activate(control)
            } else { self.store.perform(control) }
        }
        _ = shortcuts.sync(settings.shortcuts)
        NotificationCenter.default.addObserver(self, selector: #selector(syncSettings), name: .settingsChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontAppChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hidePanel() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible { self.hidePanel(); return nil }
            if event.type != .keyDown && event.window != self.panel && event.window != self.statusItem.button?.window { self.hidePanel() }
            return event
        }
        store.refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            if self?.panel.isVisible == true { self?.store.refresh() }
        }
        if !settings.defaults.bool(forKey: "onboardingSeen") && !AXIsProcessTrusted() { showGuide() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-controls") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() } }
        #endif
    }
    @objc private func frontAppChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != getpid() { store.previousApp = app }
    }
    @objc private func syncSettings() { _ = shortcuts.sync(settings.shortcuts) }
    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }
    private func showPanel() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { store.previousApp = front }
        guard positionPanel() else { NSSound.beep(); return }
        panel.makeKeyAndOrderFront(nil)
        store.refresh()
    }
    @discardableResult private func positionPanel() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }), anchor.minX >= screen.frame.minX, anchor.maxX <= screen.frame.maxX, anchor.maxY > screen.visibleFrame.maxY else { return false }
        let height = min(controls.desiredHeight, screen.visibleFrame.height - 12)
        let x = min(max(anchor.midX - 180, screen.visibleFrame.minX + 6), screen.visibleFrame.maxX - 366)
        panel.setFrame(NSRect(x: x, y: anchor.minY - height - 4, width: 360, height: height), display: true)
        return true
    }
    private func hidePanel() { panel?.orderOut(nil) }
    private func showPreferences(_ pane: Int) {
        hidePanel()
        if preferences == nil {
            preferences = PreferencesController(settings: settings)
            preferences?.validateShortcuts = { [weak self] in self?.shortcuts.sync($0) ?? [] }
        }
        preferences?.show(pane: pane)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow == panel && NSApp.modalWindow == nil { hidePanel() }
    }
    private func showGuide() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = settings.text("辅助功能", "Accessibility"); window.isReleasedWhenClosed = false
        let icon = NSImageView(); icon.image = Brand.icon(size: 48); icon.widthAnchor.constraint(equalToConstant: 48).isActive = true; icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let title = label(settings.text("开启辅助功能权限", "Enable Accessibility"), size: 19, weight: .medium)
        let detail = NSTextField(wrappingLabelWithString: settings.text("授权后可使用专注模式、键盘清洁与系统控制。", "Grant access to use Focus, keyboard cleaning and system controls.")); detail.alignment = .center; detail.textColor = .secondaryLabelColor
        let button = ActionButton(title: settings.text("打开辅助功能设置", "Open Accessibility Settings")) { SystemSettings.requestAccessibility() }; button.bezelStyle = .rounded; button.showsBorderOnlyWhileMouseInside = false
        let stack = NSStackView(views: [icon, title, detail, button]); stack.orientation = .vertical; stack.spacing = 16
        let host = NSView(); window.contentView = host; fill(stack, in: host, inset: 30)
        window.center(); guide = window; NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        settings.defaults.set(true, forKey: "onboardingSeen")
        guideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak window] timer in
            guard let self, let window, window.isVisible else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate(); title.stringValue = self.settings.text("辅助功能已开启", "Accessibility Enabled")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { window.orderOut(nil) }
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true; hidePanel()
        store.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        guideTimer?.invalidate(); refreshTimer?.invalidate(); store.cleaning.stopAll()
    }
}
