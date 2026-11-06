import AppKit
import Carbon

final class ShortcutManager {
    private var refs: [EventHotKeyRef] = []
    private var ids: [UInt32: String] = [:]
    private var handler: EventHandlerRef?
    var onTrigger: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard status == noErr else { return status }
            let owner = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            if let id = owner.ids[hotkey.id] { owner.onTrigger?(id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func sync(_ shortcuts: [String: Shortcut]) -> [String] {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); ids.removeAll()
        var failures: [String] = []
        for (index, entry) in shortcuts.sorted(by: { $0.key < $1.key }).enumerated() {
            var ref: EventHotKeyRef?
            let tag = UInt32(index + 1)
            let status = RegisterEventHotKey(entry.value.keyCode, entry.value.modifiers, EventHotKeyID(signature: 0x4F434F4B, id: tag), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref); ids[tag] = entry.key }
            else { failures.append(entry.key) }
        }
        return failures
    }
    deinit { refs.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
}

final class ShortcutButton: NSButton {
    var onRecord: ((Shortcut?) -> Void)?
    private var recording = false
    private var originalTitle = ""
    var emptyTitle = "录制快捷键"
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); bezelStyle = .rounded; controlSize = .small; font = .systemFont(ofSize: 11)
        target = self; action = #selector(record)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    @objc private func record() { originalTitle = title; recording = true; title = "…"; window?.makeFirstResponder(self) }
    override func resignFirstResponder() -> Bool { if recording { title = originalTitle }; recording = false; return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = originalTitle; return }
        if event.keyCode == 51 || event.keyCode == 117 { recording = false; onRecord?(nil); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        var carbon: UInt32 = 0; var display = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); display += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); display += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); display += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); display += "⌘" }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"]
        display += special[event.keyCode] ?? (event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)")
        recording = false
        onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbon, display: display))
    }
}
