import AppKit
import ServiceManagement
import SwiftUI

final class PreferencesController: NSWindowController {
    let settings: Settings
    let controls: ControlListPreferences
    private let model: PreferencesModel
    var selectedPane: Int { model.selectedPane ?? 0 }

    init(settings: Settings) {
        self.settings = settings
        controls = ControlListPreferences(settings: settings)
        model = PreferencesModel(settings: settings)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = settings.text("设置", "Settings")
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 620, height: 460)
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: PreferencesRoot(model: model, controls: controls))
        window.setContentSize(NSSize(width: 660, height: 500))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func selectPane(_ pane: Int) { model.selectedPane = pane == 1 ? 1 : 0 }
    func show(pane: Int) {
        selectPane(pane)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class PreferencesModel: ObservableObject {
    let settings: Settings
    @Published var selectedPane: Int? = 0
    @Published var english: Bool {
        didSet { if settings.english != english { settings.english = english } }
    }
    @Published var theme: AppTheme {
        didSet { if settings.theme != theme { settings.theme = theme } }
    }
    @Published private var revision = 0
    private var observer: NSObjectProtocol?
    init(settings: Settings) {
        self.settings = settings
        english = settings.english
        theme = settings.theme
        observer = NotificationCenter.default.addObserver(forName: .settingsChanged, object: settings, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.english = settings.english
            self.theme = settings.theme
            self.revision &+= 1
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func text(_ zh: String, _ en: String) -> String { settings.text(zh, en) }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { NSAlert(error: error).runModal() }
        revision &+= 1
    }
}

private struct PreferencesRoot: View {
    @ObservedObject var model: PreferencesModel
    let controls: ControlListPreferences
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedPane) {
                Label { Text(model.text("基础设置", "General")) } icon: { SettingsBadge(symbol: "gearshape.fill", color: .gray) }.tag(0)
                Label { Text(model.text("控制项", "Controls")) } icon: { SettingsBadge(symbol: "slider.horizontal.3", color: .blue) }.tag(1)
            }
            .listStyle(.sidebar)
            .modifier(FixedSettingsSidebar())
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
            .safeAreaInset(edge: .bottom, spacing: 0) { ContactLinks(english: model.english) }
        } detail: {
            Group {
                if model.selectedPane == 1 {
                    ControlsPreferencesView(controller: controls, english: model.english)
                } else {
                    GeneralPreferencesView(model: model)
                }
            }
            .navigationTitle(model.selectedPane == 1 ? model.text("控制项", "Controls") : model.text("基础设置", "General"))
        }
        .navigationSplitViewStyle(.balanced)
        .font(.system(size: 14))
    }
}

private struct SettingsBadge: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct FixedSettingsSidebar: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14, *) { content.toolbar(removing: .sidebarToggle) }
        else { content }
    }
}

private struct ContactLinks: View {
    let english: Bool

    var body: some View {
        List(selection: .constant(Set<String>())) {
            contactLink(english ? "Email" : "邮箱", icon: "ContactEmail", color: .gray, url: "mailto:niallyoung2002@gmail.com")
            contactLink("GitHub", icon: "ContactGitHub", color: .black, url: "https://github.com/Niall-Young")
            contactLink("X/Twitter", icon: "ContactX", color: .black, url: "https://x.com/NiallxYoung")
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .buttonStyle(.plain)
        .frame(height: 116)
    }

    @ViewBuilder private func contactLink(_ title: String, icon: String, color: Color, url: String) -> some View {
        let link = Link(destination: URL(string: url)!) {
            Label {
                Text(title)
            } icon: {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 14))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .help(url)
        if #available(macOS 14, *) { link.selectionDisabled() }
        else { link }
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var model: PreferencesModel
    var body: some View {
        Form {
            Section {
                Toggle(model.text("登录时启动", "Launch at login"), isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                Picker(model.text("语言", "Language"), selection: $model.english) {
                    Text("简体中文").tag(false)
                    Text("English").tag(true)
                }
                Picker(model.text("主题色", "Appearance"), selection: $model.theme) {
                    Text(model.text("跟随系统", "System")).tag(AppTheme.system)
                    Text(model.text("亮色", "Light")).tag(AppTheme.light)
                    Text(model.text("暗色", "Dark")).tag(AppTheme.dark)
                }
                LabeledContent(model.text("辅助功能", "Accessibility")) {
                    Button(model.text("打开系统设置", "Open System Settings")) { SystemSettings.requestAccessibility() }
                }
            } header: {
                Text(model.text("系统", "System")).font(.system(size: 14, weight: .semibold))
            }
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? Brand.icon(size: 40))
                        .resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GhostCook").font(.system(size: 14, weight: .semibold))
                        Text(model.text("版本 ", "Version ") + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"))
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            } header: {
                Text(model.text("关于", "About")).font(.system(size: 14, weight: .semibold))
            }
        }
        .formStyle(.grouped)
    }
}

private struct ControlsPreferencesView: NSViewControllerRepresentable {
    let controller: ControlListPreferences
    let english: Bool
    func makeNSViewController(context: Context) -> ControlListPreferences { controller }
    func updateNSViewController(_ nsViewController: ControlListPreferences, context: Context) { nsViewController.refreshLanguage() }
}

private final class ControlsSearchField: NSSearchField {
    static let cornerRadius: CGFloat = 12

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        cell?.drawInterior(withFrame: bounds, in: self)
    }
}

final class ControlListPreferences: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let settings: Settings
    private let table = NSTableView()
    private let search = ControlsSearchField()
    private let dragType = NSPasteboard.PasteboardType("dev.nialyoung.onecook.control")
    private var items: [Control] { settings.controls.filter { search.stringValue.isEmpty || $0.zh.localizedCaseInsensitiveContains(search.stringValue) || $0.en.localizedCaseInsensitiveContains(search.stringValue) } }
    init(settings: Settings) { self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 449, height: 512))
        search.bezelStyle = .squareBezel
        search.controlSize = .regular
        search.font = .systemFont(ofSize: 14)
        search.placeholderString = settings.text("搜索控制项", "Search controls")
        search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("control"))
        column.width = 393
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 44
        table.intercellSpacing = .zero
        table.style = .plain
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.selectionHighlightStyle = .none
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .clear
        table.registerForDraggedTypes([dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.automaticallyAdjustsContentInsets = false
        let group = NSBox()
        group.boxType = .custom
        group.titlePosition = .noTitle
        group.borderWidth = 0
        group.cornerRadius = ControlsSearchField.cornerRadius
        group.contentViewMargins = .zero
        if #available(macOS 14, *) { group.fillColor = .quaternarySystemFill }
        else { group.fillColor = .controlBackgroundColor }
        group.wantsLayer = true
        group.layer?.cornerRadius = ControlsSearchField.cornerRadius
        group.layer?.masksToBounds = true
        for child in [search, group, scroll] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), search.topAnchor.constraint(equalTo: view.topAnchor, constant: 16), search.heightAnchor.constraint(equalToConstant: 28),
            group.leadingAnchor.constraint(equalTo: search.leadingAnchor), group.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor, constant: -4), group.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16), group.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            scroll.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 4), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4), scroll.topAnchor.constraint(equalTo: group.topAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: group.bottomAnchor, constant: -4)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .settingsChanged, object: nil)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        table.layoutSubtreeIfNeeded()
        if !items.isEmpty { table.scrollRowToVisible(0) }
    }
    func refreshLanguage() {
        guard isViewLoaded else { return }
        search.placeholderString = settings.text("搜索控制项", "Search controls")
        table.reloadData()
    }
    @objc private func reload() { refreshLanguage() }
    func controlTextDidChange(_ obj: Notification) { table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let control = items[row]
        let cell = NSTableCellView()
        let icon = NSImageView(); icon.image = NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil); icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
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
            icon.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 12), icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
