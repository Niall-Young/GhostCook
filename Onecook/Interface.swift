import AppKit

extension AppTheme {
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class MenuActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, state: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self; self.state = state ? .on : .off
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { handler() }
}
final class ActionButton: NSButton {
    var handler: (() -> Void)?
    convenience init(title: String = "", symbol: String? = nil, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title; self.font = .systemFont(ofSize: 14); self.handler = handler; target = self; action = #selector(invoke)
        bezelStyle = title.isEmpty && symbol != nil ? .regularSquare : .recessed
        showsBorderOnlyWhileMouseInside = true
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
    }
    @objc private func invoke() { handler?() }
}
final class ControlSwitch: NSSwitch {
    var handler: (() -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    @objc private func invoke() { handler?() }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ControlIconView: NSImageView {
    init(symbol: String) {
        super.init(frame: NSRect(x: 21, y: 17.5, width: 20, height: 20))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imageScaling = .scaleProportionallyUpOrDown
        contentTintColor = .secondaryLabelColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

func label(_ text: String, size: CGFloat = 14, color: NSColor = .labelColor, weight: NSFont.Weight = .regular) -> NSTextField {
    let value = NSTextField(labelWithString: text)
    value.font = .systemFont(ofSize: max(14, size), weight: weight); value.textColor = color
    value.lineBreakMode = .byTruncatingTail
    return value
}
func fill(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
    parent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
}

final class ControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

final class ControlsViewController: NSViewController {
    let store: ControlStore
    var settings: Settings { store.settings }
    var onSettings: ((Int) -> Void)?
    var onResize: (() -> Void)?
    var onQuit: (() -> Void)?
    private var host: NSView!
    private var rows: [String: (ControlSwitch, NSTextField, NSProgressIndicator, ControlIconView)] = [:]
    private var secondaryMenus: [NSMenu] = []
    private let topPadding: CGFloat = 12
    private let footerHeight: CGFloat = 66
    var desiredHeight: CGFloat { topPadding + 1 + footerHeight + CGFloat(min(max(settings.selectedControls.count, 1), 8)) * 55 }
    init(store: ControlStore) {
        self.store = store; super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateStates), name: .controlsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        let frame = NSRect(x: 0, y: 0, width: 360, height: desiredHeight)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular; glass.tintColor = nil; glass.cornerRadius = 18
            let content = NSView(frame: frame); content.autoresizingMask = [.width, .height]
            glass.contentView = content; host = content; view = glass
        } else {
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .popover; blur.blendingMode = .behindWindow; blur.state = .active
            blur.wantsLayer = true; blur.layer?.cornerRadius = 12; blur.layer?.masksToBounds = true
            host = blur; view = blur
        }
        rebuild()
    }
    @objc func rebuild() {
        guard isViewLoaded else { return }
        host.subviews.forEach { $0.removeFromSuperview() }; rows.removeAll(); secondaryMenus.removeAll()
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .width
        stack.edgeInsets = NSEdgeInsets(top: topPadding, left: 0, bottom: 0, right: 0)
        fill(stack, in: host)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = settings.selectedControls.count > 8; scroll.autohidesScrollers = true
        let controls = settings.selectedControls
        scroll.heightAnchor.constraint(equalToConstant: CGFloat(min(max(controls.count, 1), 8)) * 55).isActive = true
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 360, height: CGFloat(max(controls.count, 1)) * 55))
        document.autoresizingMask = [.width]
        if controls.isEmpty {
            let button = ActionButton(title: settings.text("自定义控制项", "Customise controls")) { [weak self] in self?.onSettings?(1) }
            button.frame = NSRect(x: 100, y: 12, width: 160, height: 30); document.addSubview(button)
        }
        for (index, control) in controls.enumerated() {
            document.addSubview(makeRow(control, y: CGFloat(index) * 55))
        }
        scroll.documentView = document; stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(separator())
        let footer = NSView(); footer.heightAnchor.constraint(equalToConstant: footerHeight).isActive = true
        let prefs = ActionButton(title: "", symbol: "slider.horizontal.3") { [weak self] in self?.onSettings?(0) }
        prefs.frame = NSRect(x: 14, y: 16, width: 34, height: 34); prefs.toolTip = settings.text("设置", "Settings"); prefs.setAccessibilityLabel(prefs.toolTip)
        let quit = ActionButton(title: "", symbol: "power") { [weak self] in self?.onQuit?() }
        quit.frame = NSRect(x: 312, y: 16, width: 34, height: 34); quit.toolTip = settings.text("退出 GhostCook", "Quit GhostCook"); quit.setAccessibilityLabel(quit.toolTip)
        [prefs, quit].forEach { footer.addSubview($0) }
        stack.addArrangedSubview(footer)
        updateStates(); onResize?()
    }
    private func separator() -> NSView {
        let container = NSView(); container.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let box = NSBox(); box.boxType = .separator; box.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(box)
        NSLayoutConstraint.activate([box.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), box.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), box.centerYAnchor.constraint(equalTo: container.centerYAnchor)])
        return container
    }
    private func makeRow(_ control: Control, y: CGFloat) -> NSView {
        let row = FlippedView(frame: NSRect(x: 0, y: y, width: 360, height: 55)); row.autoresizingMask = [.width]
        let icon = ControlIconView(symbol: control.symbol)
        let title = label(settings.english ? control.en : control.zh)
        let titleHeight = title.fittingSize.height
        title.frame = NSRect(x: 60, y: (row.bounds.height - titleHeight) / 2, width: 232, height: titleHeight)
        let toggle = ControlSwitch(frame: .zero)
        toggle.sizeToFit()
        let switchSize = toggle.frame.size
        toggle.setFrameSize(NSSize(width: switchSize.width * 0.75, height: switchSize.height * 0.75))
        toggle.setBoundsSize(switchSize)
        toggle.setFrameOrigin(NSPoint(x: 344 - toggle.frame.width, y: (row.bounds.height - toggle.frame.height) / 2))
        toggle.setAccessibilityLabel(title.stringValue)
        toggle.handler = { [weak self, weak toggle] in guard let self, let toggle else { return }; self.activate(control, from: toggle) }
        let progress = NSProgressIndicator(frame: NSRect(x: 316, y: 20, width: 16, height: 16)); progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        [icon, title, toggle, progress].forEach { row.addSubview($0) }
        if control.id == "ejectDisk" {
            let menu = NSMenu(); menu.font = .systemFont(ofSize: 14); menu.delegate = self; toggle.menu = menu
            let press = NSPressGestureRecognizer(target: self, action: #selector(protectDisks(_:))); press.minimumPressDuration = 0.45; toggle.addGestureRecognizer(press)
        }
        rows[control.id] = (toggle, title, progress, icon)
        return row
    }
    @objc private func protectDisks(_ gesture: NSPressGestureRecognizer) {
        if gesture.state == .began, let source = gesture.view { showVolumes(from: source) }
    }
    @objc func updateStates() {
        for control in settings.selectedControls {
            guard let (toggle, title, progress, icon) = rows[control.id] else { continue }
            let state = store.state(control.id)
            icon.contentTintColor = state.enabled
                ? NSColor.systemBlue.blended(withFraction: 0.35, of: .labelColor)
                : .secondaryLabelColor
            toggle.state = state.busy || state.enabled ? .on : .off
            toggle.isEnabled = state.available && !state.busy
            toggle.isHidden = state.busy
            if state.busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
            title.textColor = state.available ? .labelColor : .secondaryLabelColor
            if control.id == "airpods", let name = store.audioDeviceName { title.stringValue = name }
        }
    }
    func activate(_ control: Control, from source: NSView? = nil) {
        let source = source ?? rows[control.id]?.0 ?? view
        if control.id == "resolution" { rows[control.id]?.0.state = .off; showResolutions(from: source); return }
        if control.isTimed && !store.state(control.id).enabled {
            rows[control.id]?.0.state = .off
            let menu = NSMenu(); menu.font = .systemFont(ofSize: 14)
            for (zh, en, seconds) in [("30 分钟", "30 minutes", 1800.0), ("1 小时", "1 hour", 3600.0), ("2 小时", "2 hours", 7200.0), ("4 小时", "4 hours", 14400.0)] {
                menu.addItem(MenuActionItem(settings.text(zh, en)) { [weak self] in self?.store.perform(control, enabled: true, duration: seconds) })
            }
            menu.addItem(MenuActionItem(settings.text("直到今天结束", "Until the end of today")) { [weak self] in
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
                self?.store.perform(control, enabled: true, duration: tomorrow.timeIntervalSinceNow)
            })
            menu.addItem(.separator())
            menu.addItem(MenuActionItem(settings.text("不定时", "No timer")) { [weak self] in self?.store.perform(control, enabled: true) })
            popup(menu, from: source); return
        }
        if control.needsConfirmation {
            rows[control.id]?.0.state = .off
            let alert = NSAlert(); alert.messageText = settings.english ? control.en : control.zh
            let details: [String: (String, String)] = [
                "emptyTrash": ("废纸篓中的文件将被永久删除。", "Files in the Trash will be permanently deleted."),
                "clearDownloads": ("将“下载”文件夹内的所有内容移到废纸篓。", "Move all Downloads contents to the Trash."),
                "xcodeClean": ("将全部 Xcode 派生数据移到废纸篓。", "Move all Xcode derived data to the Trash."),
                "quitApps": ("正常退出其他应用，保留当前应用、GhostCook 与 Finder。", "Quit other apps normally, keeping your current app, GhostCook and Finder."),
                "ejectDisk": ("推出所有未受保护的外接磁盘与磁盘映像。", "Eject all unprotected external disks and disk images.")
            ]
            if let (zh, en) = details[control.id] { alert.informativeText = settings.text(zh, en) }
            alert.addButton(withTitle: settings.text("继续", "Continue")); alert.addButton(withTitle: settings.text("取消", "Cancel")); alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { updateStates(); return }
        }
        store.perform(control)
    }
    func showVolumes(from source: NSView) {
        let menu = NSMenu(title: settings.text("受保护的磁盘", "Protected disks")); menu.font = .systemFont(ofSize: 14)
        let title = NSMenuItem(title: menu.title, action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        let volumes = Volumes.inventory()
        if volumes.isEmpty { menu.addItem(withTitle: settings.text("当前没有可推出的磁盘", "No ejectable disks"), action: nil, keyEquivalent: "") }
        for volume in volumes {
            menu.addItem(MenuActionItem(volume.name, state: settings.protectedVolumes.contains(volume.id)) { [weak self] in
                guard let self else { return }
                if self.settings.protectedVolumes.contains(volume.id) { self.settings.protectedVolumes.removeAll { $0 == volume.id } }
                else { self.settings.protectedVolumes.append(volume.id) }
            })
        }
        popup(menu, from: source)
    }
    private func showResolutions(from source: NSView) {
        let menu = NSMenu(); menu.font = .systemFont(ofSize: 14)
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = CGDirectDisplayID(number.uint32Value)
            let submenu = NSMenu(); submenu.font = .systemFont(ofSize: 14)
            for choice in Displays.choices(for: display) {
                let selected = CGDisplayCopyDisplayMode(display)?.ioDisplayModeID == choice.mode.ioDisplayModeID
                submenu.addItem(MenuActionItem(choice.title, state: selected) { [weak self] in
                    do { try Displays.set(choice) } catch { self?.store.onError?(Control.all.first { $0.id == "resolution" }!, error) }
                })
            }
            let item = NSMenuItem(title: screen.localizedName, action: nil, keyEquivalent: ""); item.submenu = submenu; menu.addItem(item)
        }
        popup(menu, from: source)
    }
    private func popup(_ menu: NSMenu, from source: NSView) { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: source.bounds.minY - 4), in: source); updateStates() }
}
extension ControlsViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(MenuActionItem(settings.text("受保护的磁盘…", "Protected disks…")) { [weak self] in guard let self else { return }; self.showVolumes(from: self.rows["ejectDisk"]?.0 ?? self.view) })
    }
}
