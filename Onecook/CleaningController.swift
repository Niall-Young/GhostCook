import AppKit
import ApplicationServices

final class CleaningController {
    private var keyboardTap: CFMachPort?
    private var keyboardSource: CFRunLoopSource?
    private var windows: [NSWindow] = []
    private var escapeTimer: Timer?
    private var escapeStart: Date?
    var onScreenStopped: (() -> Void)?
    var keyboardActive: Bool { keyboardTap != nil }
    var screenActive: Bool { !windows.isEmpty }

    func setKeyboard(_ enabled: Bool) throws {
        if !enabled { stopKeyboard(); return }
        if keyboardActive { return }
        guard AXIsProcessTrusted() else { throw OperationError("需要辅助功能权限 / Accessibility permission required") }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<CleaningController>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.keyboardTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return nil
        }, userInfo: context) else { throw OperationError("无法锁定键盘，请检查辅助功能权限 / Cannot lock keyboard; check Accessibility permission") }
        keyboardTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        keyboardSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func stopKeyboard() {
        if let tap = keyboardTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = keyboardSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        keyboardSource = nil; keyboardTap = nil
    }
    func setScreen(_ enabled: Bool, settings: Settings) {
        if !enabled { stopScreen(); return }
        if screenActive { return }
        for screen in NSScreen.screens {
            let window = CleaningWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let title = NSTextField(labelWithString: settings.text("屏幕清洁", "Screen cleaning"))
            title.font = .systemFont(ofSize: 22, weight: .medium); title.textColor = .white
            let hint = NSTextField(labelWithString: settings.text("长按 Esc 退出", "Hold Esc to finish"))
            hint.textColor = .lightGray
            let stack = NSStackView(views: [title, hint]); stack.orientation = .vertical; stack.spacing = 12
            content.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor), stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
            window.contentView = content
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        escapeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if CGEventSource.keyState(.combinedSessionState, key: 53) {
                if self.escapeStart == nil { self.escapeStart = Date() }
                if Date().timeIntervalSince(self.escapeStart!) >= 1.2 { self.stopScreen(); self.onScreenStopped?() }
            } else { self.escapeStart = nil }
        }
    }
    func stopScreen() { escapeTimer?.invalidate(); escapeTimer = nil; escapeStart = nil; windows.forEach { $0.orderOut(nil) }; windows.removeAll() }
    func stopAll() { stopKeyboard(); stopScreen() }
}
private final class CleaningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func cancelOperation(_ sender: Any?) {}
}
