import AppKit
import ServiceManagement

final class PreferencesController: NSWindowController {
    let settings: Settings
    private var lastLanguage: Bool
    private var content: PreferencesContent!

    init(settings: Settings) {
        self.settings = settings
        lastLanguage = settings.english
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = settings.text("Onecook 设置", "Onecook Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        super.init(window: window)
        populate()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .settingsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func languageChanged() {
        guard lastLanguage != settings.english else { return }
        lastLanguage = settings.english
        populate()
    }
    private func populate() {
        content = PreferencesContent(settings: settings)
        window?.contentViewController = content
        window?.title = settings.text("Onecook 设置", "Onecook Settings")
    }
    func show(pane: Int) {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if pane == 1 { content.focusSearch() }
    }
}

private final class PreferencesContent: NSViewController {
    private let settings: Settings
    private let controls: ControlListPreferences
    init(settings: Settings) {
        self.settings = settings
        controls = ControlListPreferences(settings: settings)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 540))
        let sidebar: NSView
        let sidebarContent = NSView()
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.contentView = sidebarContent
            sidebar = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .sidebar
            blur.blendingMode = .behindWindow
            sidebar = blur
            fill(sidebarContent, in: blur)
        }
        let general = GeneralPreferences(settings: settings)
        addChild(general)
        addChild(controls)
        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        let name = label("Onecook", size: 20, weight: .semibold)
        let version = label(settings.text("版本 ", "Version ") + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"), size: 11, color: .secondaryLabelColor)
        let identity = NSStackView(views: [name, version])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 4
        let github = ActionButton(title: "GitHub", symbol: "arrow.up.right") {
            NSWorkspace.shared.open(URL(string: "https://github.com/Cherry-Yiran/OneTouch")!)
        }
        github.imagePosition = .imageTrailing
        github.bezelStyle = .inline
        github.contentTintColor = .secondaryLabelColor
        let divider = NSBox()
        divider.boxType = .separator
        for child in [sidebar, controls.view, divider] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        for child in [icon, identity, general.view, github] { sidebarContent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor), sidebar.topAnchor.constraint(equalTo: view.topAnchor), sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 250),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), divider.topAnchor.constraint(equalTo: view.topAnchor), divider.bottomAnchor.constraint(equalTo: view.bottomAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            controls.view.leadingAnchor.constraint(equalTo: divider.trailingAnchor), controls.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), controls.view.topAnchor.constraint(equalTo: view.topAnchor, constant: 28), controls.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: sidebarContent.leadingAnchor, constant: 22), icon.topAnchor.constraint(equalTo: sidebarContent.topAnchor, constant: 54), icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48),
            identity.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), identity.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            general.view.leadingAnchor.constraint(equalTo: sidebarContent.leadingAnchor, constant: 24), general.view.trailingAnchor.constraint(equalTo: sidebarContent.trailingAnchor, constant: -24), general.view.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 36), general.view.heightAnchor.constraint(equalToConstant: 230),
            github.leadingAnchor.constraint(equalTo: general.view.leadingAnchor), github.bottomAnchor.constraint(equalTo: sidebarContent.bottomAnchor, constant: -22)
        ])
    }
    func focusSearch() { controls.focusSearch() }
}

final class GeneralPreferences: NSViewController {
    let settings: Settings
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView()
        let language = NSPopUpButton()
        language.addItems(withTitles: ["简体中文", "English"])
        language.selectItem(at: settings.english ? 1 : 0)
        language.target = self
        language.action = #selector(setLanguage(_:))
        language.setAccessibilityLabel(settings.text("语言", "Language"))
        let login = ControlSwitch(frame: .zero); login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.setAccessibilityLabel(settings.text("登录时启动", "Launch at login"))
        login.handler = { [weak login] in
            guard let login else { return }
            do {
                if login.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            } catch {
                login.state = SMAppService.mainApp.status == .enabled ? .on : .off
                let alert = NSAlert(error: error); alert.runModal()
            }
        }
        let permission = ActionButton(title: settings.text("打开系统设置", "Open System Settings")) { SystemSettings.requestAccessibility() }
        permission.bezelStyle = .rounded; permission.showsBorderOnlyWhileMouseInside = false
        let languageTitle = label(settings.text("语言", "Language"), size: 12, color: .secondaryLabelColor)
        let launchTitle = label(settings.text("登录时启动", "Launch at login"), size: 13)
        let permissionTitle = label(settings.text("辅助功能", "Accessibility"), size: 12, color: .secondaryLabelColor)
        permission.title = settings.text("系统设置…", "System Settings…")
        permission.controlSize = .regular
        for child in [languageTitle, language, launchTitle, login, permissionTitle, permission] {
            view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            languageTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor), languageTitle.topAnchor.constraint(equalTo: view.topAnchor),
            language.leadingAnchor.constraint(equalTo: view.leadingAnchor), language.trailingAnchor.constraint(equalTo: view.trailingAnchor), language.topAnchor.constraint(equalTo: languageTitle.bottomAnchor, constant: 8),
            launchTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor), launchTitle.topAnchor.constraint(equalTo: language.bottomAnchor, constant: 25),
            login.trailingAnchor.constraint(equalTo: view.trailingAnchor), login.centerYAnchor.constraint(equalTo: launchTitle.centerYAnchor),
            permissionTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor), permissionTitle.topAnchor.constraint(equalTo: launchTitle.bottomAnchor, constant: 28),
            permission.leadingAnchor.constraint(equalTo: view.leadingAnchor), permission.topAnchor.constraint(equalTo: permissionTitle.bottomAnchor, constant: 8)
        ])
    }
    @objc private func setLanguage(_ sender: NSPopUpButton) { settings.english = sender.indexOfSelectedItem == 1 }
}

final class ControlListPreferences: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let settings: Settings
    private let table = NSTableView()
    private let search = NSSearchField()
    private let dragType = NSPasteboard.PasteboardType("dev.nialyoung.onecook.control")
    private var items: [Control] { settings.controls.filter { search.stringValue.isEmpty || $0.zh.localizedCaseInsensitiveContains(search.stringValue) || $0.en.localizedCaseInsensitiveContains(search.stringValue) } }
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 449, height: 512))
        let heading = label(settings.text("控制项", "Controls"), size: 20, weight: .semibold)
        search.controlSize = .regular
        search.placeholderString = settings.text("搜索控制项", "Search controls")
        search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("control"))
        column.width = 393
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 40
        table.intercellSpacing = .zero
        table.style = .inset
        table.selectionHighlightStyle = .none
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .clear
        table.registerForDraggedTypes([dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.automaticallyAdjustsContentInsets = false
        for child in [heading, search, scroll] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            search.leadingAnchor.constraint(equalTo: heading.leadingAnchor), search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), search.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18), search.heightAnchor.constraint(equalToConstant: 28),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 14), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .settingsChanged, object: nil)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        table.layoutSubtreeIfNeeded()
        if !items.isEmpty { table.scrollRowToVisible(0) }
    }
    func focusSearch() { view.window?.makeFirstResponder(search) }
    @objc private func reload() { guard isViewLoaded else { return }; table.reloadData() }
    func controlTextDidChange(_ obj: Notification) { table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let control = items[row]
        let cell = NSTableCellView()
        let icon = NSImageView(); icon.image = NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil); icon.contentTintColor = .secondaryLabelColor
        let title = label(settings.english ? control.en : control.zh, size: 14)
        let accessory: NSView
        let check = NSButton(checkboxWithTitle: "", target: nil, action: nil); check.controlSize = .mini; check.state = settings.visible.contains(control.id) ? .on : .off
        check.setAccessibilityLabel(settings.english ? control.en : control.zh)
        let target = VisibilityTarget { [weak self] in self?.settings.toggleVisibility(control.id) }
        check.target = target; check.action = #selector(VisibilityTarget.invoke)
        objc_setAssociatedObject(check, &visibilityTargetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        accessory = check
        let grip = NSImageView(); grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil); grip.contentTintColor = .tertiaryLabelColor
        for element in [grip, icon, title, accessory] { cell.addSubview(element); element.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), grip.centerYAnchor.constraint(equalTo: cell.centerYAnchor), grip.widthAnchor.constraint(equalToConstant: 14),
            icon.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 12), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), title.centerYAnchor.constraint(equalTo: cell.centerYAnchor), title.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -8),
            accessory.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), accessory.centerYAnchor.constraint(equalTo: cell.centerYAnchor), accessory.widthAnchor.constraint(equalToConstant: 18)
        ])
        return cell
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem(); item.setString(items[row].id, forType: dragType); return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation { dropOperation == .above ? .move : [] }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = info.draggingPasteboard.string(forType: dragType), Control.all.contains(where: { $0.id == id }) else { return false }
        let current = items
        if row < current.count && current[row].id == id { return false }
        settings.move(id, before: row < current.count ? current[row].id : nil)
        return true
    }
}
private var visibilityTargetKey: UInt8 = 0
private final class VisibilityTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}
