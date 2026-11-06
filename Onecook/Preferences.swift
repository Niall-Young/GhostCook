import AppKit
import ServiceManagement

final class PreferencesController: NSWindowController {
    let settings: Settings
    private var lastLanguage: Bool
    private var content: PreferencesContent!

    init(settings: Settings) {
        self.settings = settings
        lastLanguage = settings.english
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 540), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
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
        let selected = content?.selectedPane ?? 0
        content = PreferencesContent(settings: settings)
        content.selectPane(selected)
        window?.contentViewController = content
        window?.title = settings.text("Onecook 设置", "Onecook Settings")
    }
    func show(pane: Int) {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        content.selectPane(pane)
    }
}

private final class PreferencesContent: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let settings: Settings
    private let controls: ControlListPreferences
    private let general: GeneralPreferences
    private let navigation = NSTableView()
    private let pageHost = NSView()
    private(set) var selectedPane = 0
    init(settings: Settings) {
        self.settings = settings
        controls = ControlListPreferences(settings: settings)
        general = GeneralPreferences(settings: settings)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 740, height: 540))
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        navigation.addTableColumn(column)
        navigation.headerView = nil
        navigation.style = .sourceList
        navigation.rowHeight = 34
        navigation.backgroundColor = .clear
        navigation.focusRingType = .none
        navigation.delegate = self
        navigation.dataSource = self
        navigation.setAccessibilityLabel(settings.text("设置分类", "Settings categories"))
        let navScroll = NSScrollView()
        navScroll.drawsBackground = false
        navScroll.documentView = navigation
        navScroll.automaticallyAdjustsContentInsets = false
        let contact = preferenceGroup()
        let name = label("Niall Young", size: 13, weight: .semibold)
        let email = contactLink("niallyoung2002@gmail.com", url: "mailto:niallyoung2002@gmail.com", size: 10)
        let github = contactLink("GitHub · Niall-Young", url: "https://github.com/Niall-Young")
        let x = contactLink("X · @NiallxYoung", url: "https://x.com/NiallxYoung")
        let links = NSStackView(views: [name, email, github, x])
        links.orientation = .vertical
        links.alignment = .leading
        links.spacing = 10
        fill(links, in: contact.contentView!, inset: 12)
        let divider = NSBox()
        divider.boxType = .separator
        for child in [sidebar, pageHost, divider] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        for child in [navScroll, contact] { sidebarContent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor), sidebar.topAnchor.constraint(equalTo: view.topAnchor), sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 228),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), divider.topAnchor.constraint(equalTo: view.topAnchor), divider.bottomAnchor.constraint(equalTo: view.bottomAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            pageHost.leadingAnchor.constraint(equalTo: divider.trailingAnchor), pageHost.trailingAnchor.constraint(equalTo: view.trailingAnchor), pageHost.topAnchor.constraint(equalTo: view.topAnchor, constant: 28), pageHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            navScroll.leadingAnchor.constraint(equalTo: sidebarContent.leadingAnchor, constant: 8), navScroll.trailingAnchor.constraint(equalTo: sidebarContent.trailingAnchor, constant: -8), navScroll.topAnchor.constraint(equalTo: sidebarContent.topAnchor, constant: 54), navScroll.bottomAnchor.constraint(equalTo: contact.topAnchor, constant: -20),
            contact.leadingAnchor.constraint(equalTo: sidebarContent.leadingAnchor, constant: 12), contact.trailingAnchor.constraint(equalTo: sidebarContent.trailingAnchor, constant: -12), contact.bottomAnchor.constraint(equalTo: sidebarContent.bottomAnchor, constant: -16)
        ])
        for page in [general as NSViewController, controls] {
            addChild(page)
            fill(page.view, in: pageHost)
        }
        selectPane(selectedPane)
    }
    func selectPane(_ index: Int) {
        selectedPane = index == 1 ? 1 : 0
        guard isViewLoaded else { return }
        navigation.selectRowIndexes(IndexSet(integer: selectedPane), byExtendingSelection: false)
        general.view.isHidden = selectedPane != 0
        controls.view.isHidden = selectedPane != 1
        view.window?.makeFirstResponder(navigation)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { 2 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let title = row == 0 ? settings.text("基础设置", "General") : settings.text("控制项", "Controls")
        let cell = NSTableCellView()
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: row == 0 ? "gearshape" : "slider.horizontal.3", accessibilityDescription: nil)
        image.contentTintColor = .secondaryLabelColor
        let text = label(title, size: 13)
        cell.imageView = image
        cell.textField = text
        for child in [image, text] { cell.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard navigation.selectedRow >= 0, navigation.selectedRow != selectedPane else { return }
        selectPane(navigation.selectedRow)
    }
    private func contactLink(_ title: String, url: String, size: CGFloat = 11) -> NSButton {
        let button = ActionButton(title: title) { NSWorkspace.shared.open(URL(string: url)!) }
        button.isBordered = false
        button.font = .systemFont(ofSize: size)
        button.contentTintColor = .linkColor
        button.alignment = .left
        button.toolTip = url
        return button
    }
}

private func preferenceGroup() -> NSBox {
    let box = NSBox()
    box.boxType = .custom
    box.titlePosition = .noTitle
    box.cornerRadius = 8
    box.borderWidth = 0.5
    box.borderColor = .separatorColor
    box.fillColor = .controlBackgroundColor
    box.contentViewMargins = .zero
    return box
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
        let heading = label(settings.text("基础设置", "General"), size: 20, weight: .semibold)
        let group = preferenceGroup()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 0
        rows.alignment = .width
        let pairs: [(String, NSView)] = [
            (settings.text("语言", "Language"), language),
            (settings.text("登录时启动", "Launch at login"), login),
            (settings.text("辅助功能", "Accessibility"), permission)
        ]
        for (index, pair) in pairs.enumerated() {
            if index > 0 { let line = NSBox(); line.boxType = .separator; rows.addArrangedSubview(line) }
            let row = NSView()
            let title = label(pair.0, size: 13)
            for child in [title, pair.1] { row.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 48), title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), title.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                pair.1.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), pair.1.centerYAnchor.constraint(equalTo: row.centerYAnchor), title.trailingAnchor.constraint(lessThanOrEqualTo: pair.1.leadingAnchor, constant: -16)
            ])
            rows.addArrangedSubview(row)
        }
        fill(rows, in: group.contentView!)
        let aboutHeading = label(settings.text("关于", "About"), size: 13, color: .secondaryLabelColor, weight: .medium)
        let about = preferenceGroup()
        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.applicationIconName)
        let name = label("Onecook", size: 15, weight: .semibold)
        let version = label(settings.text("版本 ", "Version ") + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"), size: 12, color: .secondaryLabelColor)
        let identity = NSStackView(views: [name, version])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 4
        for child in [icon, identity] { about.contentView!.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        for child in [heading, group, aboutHeading, about] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            group.leadingAnchor.constraint(equalTo: heading.leadingAnchor), group.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), group.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 22),
            aboutHeading.leadingAnchor.constraint(equalTo: heading.leadingAnchor, constant: 2), aboutHeading.topAnchor.constraint(equalTo: group.bottomAnchor, constant: 28),
            about.leadingAnchor.constraint(equalTo: group.leadingAnchor), about.trailingAnchor.constraint(equalTo: group.trailingAnchor), about.topAnchor.constraint(equalTo: aboutHeading.bottomAnchor, constant: 10), about.heightAnchor.constraint(equalToConstant: 86),
            icon.leadingAnchor.constraint(equalTo: about.contentView!.leadingAnchor, constant: 14), icon.centerYAnchor.constraint(equalTo: about.contentView!.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48),
            identity.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), identity.centerYAnchor.constraint(equalTo: icon.centerYAnchor)
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
