import AppKit
import ApplicationServices

// Monochrome version of the GhostCook logo for system template rendering.
enum Brand {
    static func icon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: size / 100)
            transform.concat()

            let ghost = NSBezierPath()
            ghost.move(to: NSPoint(x: 50, y: 6))
            ghost.curve(to: NSPoint(x: 87, y: 51), controlPoint1: NSPoint(x: 76, y: 6), controlPoint2: NSPoint(x: 87, y: 26))
            ghost.curve(to: NSPoint(x: 95, y: 78), controlPoint1: NSPoint(x: 87, y: 65), controlPoint2: NSPoint(x: 91, y: 70))
            ghost.curve(to: NSPoint(x: 82, y: 87), controlPoint1: NSPoint(x: 101, y: 90), controlPoint2: NSPoint(x: 91, y: 94))
            ghost.curve(to: NSPoint(x: 71, y: 87), controlPoint1: NSPoint(x: 77, y: 83), controlPoint2: NSPoint(x: 75, y: 82))
            ghost.curve(to: NSPoint(x: 58, y: 92), controlPoint1: NSPoint(x: 66, y: 95), controlPoint2: NSPoint(x: 63, y: 97))
            ghost.curve(to: NSPoint(x: 46, y: 90), controlPoint1: NSPoint(x: 52, y: 86), controlPoint2: NSPoint(x: 52, y: 85))
            ghost.curve(to: NSPoint(x: 31, y: 92), controlPoint1: NSPoint(x: 39, y: 98), controlPoint2: NSPoint(x: 33, y: 98))
            ghost.curve(to: NSPoint(x: 23, y: 83), controlPoint1: NSPoint(x: 28, y: 86), controlPoint2: NSPoint(x: 29, y: 80))
            ghost.curve(to: NSPoint(x: 6, y: 81), controlPoint1: NSPoint(x: 11, y: 90), controlPoint2: NSPoint(x: 4, y: 88))
            ghost.curve(to: NSPoint(x: 14, y: 54), controlPoint1: NSPoint(x: 6, y: 74), controlPoint2: NSPoint(x: 13, y: 68))
            ghost.curve(to: NSPoint(x: 50, y: 6), controlPoint1: NSPoint(x: 14, y: 28), controlPoint2: NSPoint(x: 27, y: 6))
            ghost.close()

            // Transparent facial cutouts remain visible in both menu bar appearances.
            ghost.appendOval(in: NSRect(x: 37, y: 37, width: 10, height: 16))
            ghost.appendOval(in: NSRect(x: 65, y: 37, width: 10, height: 16))
            ghost.move(to: NSPoint(x: 50, y: 51))
            ghost.curve(to: NSPoint(x: 62, y: 51), controlPoint1: NSPoint(x: 54, y: 52), controlPoint2: NSPoint(x: 58, y: 52))
            ghost.curve(to: NSPoint(x: 56, y: 61), controlPoint1: NSPoint(x: 63, y: 55), controlPoint2: NSPoint(x: 60, y: 61))
            ghost.curve(to: NSPoint(x: 50, y: 51), controlPoint1: NSPoint(x: 52, y: 61), controlPoint2: NSPoint(x: 49, y: 55))
            ghost.close()
            ghost.windingRule = .evenOdd
            NSColor.black.setFill()
            ghost.fill()
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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var refreshTimer: Timer?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = settings.theme.appearance
        NotificationCenter.default.addObserver(self, selector: #selector(appearancePreferenceChanged(_:)), name: .settingsChanged, object: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Brand.icon(size: 16); button.target = self; button.action = #selector(togglePanel); button.toolTip = "GhostCook"; button.setAccessibilityLabel("GhostCook")
        }
        controls = ControlsViewController(store: store)
        controls.onSettings = { [weak self] in self?.showPreferences($0) }
        controls.onQuit = { NSApp.terminate(nil) }
        controls.onResize = { [weak self] in if self?.panel?.isVisible == true { self?.positionPanel() } }
        panel = ControlsPanel(contentRect: NSRect(origin: .zero, size: controls.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentViewController = controls; panel.delegate = self
        store.onError = { control, error in
            NSLog("GhostCook [%@]: %@", control.id, error.localizedDescription)
        }
        store.onBeforeExternalUI = { [weak self] in self?.hidePanel() }
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
        if ProcessInfo.processInfo.arguments.contains("--show-settings") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPreferences(0) } }
        if ProcessInfo.processInfo.arguments.contains("--show-controls") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPanel() } }
        #endif
    }
    @objc private func appearancePreferenceChanged(_ notification: Notification) {
        guard let source = notification.object as? Settings, source === settings else { return }
        NSApp.appearance = settings.theme.appearance
    }
    @objc private func frontAppChanged(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != getpid() { store.previousApp = app }
    }
    @objc private func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }
    private func showPanel() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { store.previousApp = front }
        guard positionPanel() else { NSSound.beep(); return }
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.invalidateShadow()
        store.refresh()
    }
    @discardableResult private func positionPanel() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }), anchor.minX >= screen.frame.minX, anchor.maxX <= screen.frame.maxX, anchor.maxY > screen.visibleFrame.maxY else { return false }
        let height = min(controls.desiredHeight, screen.visibleFrame.height - 12)
        let x = min(max(anchor.midX - 180, screen.visibleFrame.minX + 6), screen.visibleFrame.maxX - 366)
        let inset = ControlsViewController.shadowInset
        panel.setFrame(NSRect(x: x - inset, y: anchor.minY - height - 4 - inset,
                              width: 360 + inset * 2, height: height + inset * 2), display: true)
        return true
    }
    private func hidePanel() { panel?.orderOut(nil) }
    private func showPreferences(_ pane: Int) {
        hidePanel()
        if preferences == nil {
            preferences = PreferencesController(settings: settings)
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
        let detail = NSTextField(wrappingLabelWithString: settings.text("授权后可使用专注模式、键盘清洁与系统控制。", "Grant access to use Focus, keyboard cleaning and system controls.")); detail.font = .systemFont(ofSize: 14); detail.alignment = .center; detail.textColor = .secondaryLabelColor
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
