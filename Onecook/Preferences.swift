import AppKit
import ServiceManagement

final class PreferencesController: NSWindowController {
    let settings: Settings
    private let tabs = PreferenceTabs()
    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 490), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "Onecook"; window.toolbarStyle = .preference
        super.init(window: window)
        tabs.tabStyle = .toolbar
        tabs.view.frame = NSRect(x: 0, y: 0, width: 440, height: 490)
        window.contentViewController = tabs
        populate()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: .settingsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private var lastLanguage: Bool?
    @objc private func languageChanged() {
        if lastLanguage != settings.english { populate() }
    }
    private func populate() {
        let selected = tabs.selectedTabViewItemIndex
        lastLanguage = settings.english
        tabs.tabViewItems.forEach { tabs.removeTabViewItem($0) }
        let pages: [(String, String, NSViewController)] = [
            (settings.text("通用", "General"), "gearshape", GeneralPreferences(settings: settings)),
            (settings.text("自定义", "Customise"), "slider.horizontal.3", ControlListPreferences(settings: settings)),
            (settings.text("关于", "About"), "info.circle", AboutPreferences(settings: settings))
        ]
        for (title, symbol, page) in pages {
            page.title = title
            let item = NSTabViewItem(viewController: page); item.label = title; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = max(0, selected)
    }
    func show(pane: Int) {
        tabs.selectedTabViewItemIndex = pane
        window?.title = tabs.tabViewItems[pane].label
        NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
}

final class GeneralPreferences: NSViewController {
    let settings: Settings
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 490))
        let language = NSPopUpButton(); language.addItems(withTitles: ["简体中文", "English"]); language.selectItem(at: settings.english ? 1 : 0); language.target = self; language.action = #selector(setLanguage(_:))
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
        let grid = NSGridView(views: [
            [label(settings.text("语言：", "Language:")), language],
            [label(settings.text("登录时启动：", "Launch at login:")), login],
            [label(settings.text("辅助功能：", "Accessibility:")), permission]
        ])
        grid.rowSpacing = 20; grid.columnSpacing = 16; grid.column(at: 0).xPlacement = .trailing; grid.column(at: 1).xPlacement = .leading
        view.addSubview(grid); grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30), grid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20), grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 30)])
    }
    @objc private func setLanguage(_ sender: NSPopUpButton) { settings.english = sender.indexOfSelectedItem == 1 }
}

final class ControlListPreferences: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let settings: Settings
    private let table = NSTableView()
    private let search = NSSearchField()
    private var summary: NSTextField!
    private let dragType = NSPasteboard.PasteboardType("dev.nialyoung.onecook.control")
    private var items: [Control] { settings.controls.filter { search.stringValue.isEmpty || $0.zh.localizedCaseInsensitiveContains(search.stringValue) || $0.en.localizedCaseInsensitiveContains(search.stringValue) } }
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 490))
        summary = label("", size: NSFont.smallSystemFontSize, color: .secondaryLabelColor)
        summary.frame = NSRect(x: 20, y: 450, width: 400, height: 20); summary.autoresizingMask = [.minYMargin]; view.addSubview(summary)
        search.frame = NSRect(x: 20, y: 410, width: 400, height: 28); search.autoresizingMask = [.minYMargin]; search.placeholderString = settings.text("搜索控制项", "Search controls"); search.delegate = self; view.addSubview(search)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("control")); column.width = 396; table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 34; table.intercellSpacing = .zero; table.style = .inset; table.selectionHighlightStyle = .none
        table.delegate = self; table.dataSource = self; table.backgroundColor = .clear
        table.registerForDraggedTypes([dragType]); table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 400, height: 375)); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = table; view.addSubview(scroll)
        updateSummary()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .settingsChanged, object: nil)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        table.layoutSubtreeIfNeeded()
        if !items.isEmpty { table.scrollRowToVisible(0) }
    }
    private func updateSummary() {
        summary.stringValue = settings.text("选择控制项并拖动调整顺序。已选择 \(settings.visible.count)", "Select and drag to reorder. \(settings.visible.count) selected")
    }
    @objc private func reload() { guard isViewLoaded else { return }; updateSummary(); table.reloadData() }
    func controlTextDidChange(_ obj: Notification) { table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let control = items[row]
        let cell = NSTableCellView()
        let icon = NSImageView(); icon.image = NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil); icon.contentTintColor = .secondaryLabelColor
        let title = label(settings.english ? control.en : control.zh)
        let accessory: NSView
        let check = NSButton(checkboxWithTitle: "", target: nil, action: nil); check.controlSize = .mini; check.state = settings.visible.contains(control.id) ? .on : .off
        check.setAccessibilityLabel(settings.english ? control.en : control.zh)
        let target = VisibilityTarget { [weak self] in self?.settings.toggleVisibility(control.id) }
        check.target = target; check.action = #selector(VisibilityTarget.invoke)
        objc_setAssociatedObject(check, &visibilityTargetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        accessory = check
        for element in [icon, title, accessory] { cell.addSubview(element); element.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), title.centerYAnchor.constraint(equalTo: cell.centerYAnchor), title.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -8),
            accessory.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), accessory.centerYAnchor.constraint(equalTo: cell.centerYAnchor), accessory.widthAnchor.constraint(equalToConstant: 18)
        ])
        let grip = NSImageView(); grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil); grip.contentTintColor = .tertiaryLabelColor
        cell.addSubview(grip); grip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([grip.trailingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: -12), grip.centerYAnchor.constraint(equalTo: cell.centerYAnchor), grip.widthAnchor.constraint(equalToConstant: 14)])
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

final class AboutPreferences: NSViewController {
    let settings: Settings
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 490))
        let image = NSImageView(); image.image = Brand.icon(size: 64); image.setFrameSize(NSSize(width: 64, height: 64)); image.widthAnchor.constraint(equalToConstant: 64).isActive = true; image.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = label("Onecook", size: 23, weight: .semibold)
        let version = label(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0", color: .secondaryLabelColor)
        let github = ActionButton(title: "GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/Cherry-Yiran/OneTouch")!) }
        github.bezelStyle = .rounded; github.showsBorderOnlyWhileMouseInside = false
        let stack = NSStackView(views: [image, name, version, github]); stack.orientation = .vertical; stack.spacing = 14
        view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 60)])
    }
}

private final class PreferenceTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Onecook"
    }
}
