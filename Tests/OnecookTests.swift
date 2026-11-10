import XCTest
import AppKit
@testable import Onecook

final class OnecookTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: Settings!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "dev.nialyoung.onecook.tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        settings = Settings(defaults: defaults)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        settings = nil; defaults = nil
        super.tearDown()
    }
    func testCatalogHas31UniqueControlsAndValidSymbols() {
        XCTAssertEqual(Control.all.count, 31)
        XCTAssertEqual(Set(Control.all.map(\.id)).count, 31)
        for control in Control.all {
            XCTAssertNotNil(NSImage(systemSymbolName: control.symbol, accessibilityDescription: nil), control.id)
        }
    }
    func testThemeDefaultsPersistsAndRecoversFromUnknownValue() {
        XCTAssertEqual(settings.theme, .system)
        for theme in AppTheme.allCases {
            settings.theme = theme
            XCTAssertEqual(Settings(defaults: defaults).theme, theme)
        }
        defaults.set("unknown-theme", forKey: "theme")
        XCTAssertEqual(Settings(defaults: defaults).theme, .system)
    }
    func testThemeUsesSystemAppearanceWithoutChangingSystemSetting() {
        XCTAssertNil(AppTheme.system.appearance)
        XCTAssertEqual(AppTheme.light.appearance?.name, .aqua)
        XCTAssertEqual(AppTheme.dark.appearance?.name, .darkAqua)
    }
    func testCorruptAndDuplicateOrderPreservesEveryControl() {
        defaults.set(["awake", "unknown", "awake", "desktop"], forKey: "order")
        XCTAssertEqual(Array(settings.order.prefix(2)), ["awake", "desktop"])
        XCTAssertEqual(Set(settings.order), Set(Control.all.map(\.id)))
        XCTAssertEqual(settings.order.count, 31)
    }
    func testEmptyVisibilityRemainsEmptyAfterRestoring() {
        settings.visible = []
        XCTAssertTrue(Settings(defaults: defaults).selectedControls.isEmpty)
    }
    func testUnknownVisibleIDsAndDuplicatesAreRemoved() {
        settings.visible = ["awake", "bad", "awake"]
        XCTAssertEqual(settings.visible, ["awake"])
    }
    func testMoveReordersWithoutChangingSelectedControls() {
        let selected = settings.visible
        settings.move("trueTone", before: "desktop")
        XCTAssertEqual(settings.order.first, "trueTone")
        XCTAssertEqual(settings.visible, selected)
        XCTAssertEqual(settings.selectedControls.first?.id, "trueTone")
        settings.move("trueTone", before: nil)
        XCTAssertEqual(settings.order.last, "trueTone")
    }
    func testTimersPersistAcrossSettingsInstances() {
        let deadline = Date(timeIntervalSince1970: 1800000000)
        settings.deadlines = ["awake": deadline]
        let restored = Settings(defaults: defaults)
        XCTAssertEqual(restored.deadlines["awake"], deadline)
    }
    func testCorruptStoredDataDoesNotCrash() {
        defaults.set(Data("broken".utf8), forKey: "deadlines")
        XCTAssertTrue(settings.deadlines.isEmpty)
    }
    func testConfirmationPolicyMatchesDirectCleanupActions() {
        for id in ["xcodeClean", "quitApps", "ejectDisk"] {
            XCTAssertTrue(Control.all.first { $0.id == id }!.needsConfirmation)
        }
    }
    func testDownloadsAndTrashExecuteWithoutAppConfirmation() {
        for id in ["emptyTrash", "clearDownloads", "clipboard"] {
            XCTAssertFalse(Control.all.first { $0.id == id }!.needsConfirmation)
        }
    }
    @MainActor func testClipboardClickClearsAllTypesAndShowsTemporaryFeedback() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        settings.visible = ["clipboard"]
        let store = ControlStore(settings: settings, pasteboard: pasteboard)
        let controller = ControlsViewController(store: store)
        let view = controller.view
        for english in [false, true] {
            settings.english = english
            let item = NSPasteboardItem()
            item.setString("Clipboard regression", forType: .string)
            item.setString("<b>Clipboard regression</b>", forType: .html)
            item.setString(FileManager.default.temporaryDirectory.absoluteString, forType: .fileURL)
            XCTAssertTrue(pasteboard.writeObjects([item]))
            let currentToggle = try XCTUnwrap(descendants(view).compactMap { $0 as? ControlSwitch }.first)
            currentToggle.performClick(nil)
            XCTAssertTrue(pasteboard.types?.isEmpty ?? true)
            XCTAssertNil(pasteboard.string(forType: .string))
            XCTAssertNotNil(store.state("clipboard").completedAt)
            XCTAssertFalse(store.state("clipboard").busy)
            XCTAssertFalse(store.state("clipboard").enabled)
            XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains {
                $0.stringValue == (english ? "Clipboard cleared" : "剪贴板已清空")
            })
        }
        XCTAssertTrue(try XCTUnwrap(descendants(view).compactMap { $0 as? ControlSwitch }.first).isEnabled)
        let reset = XCTNSNotificationExpectation(name: .controlsChanged, object: store)
        reset.handler = { _ in store.state("clipboard").completedAt == nil }
        wait(for: [reset], timeout: 4)
        XCTAssertTrue(descendants(view).compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Clear clipboard" })
    }
    func testAppleScriptHonorsOperationTimeout() {
        XCTAssertThrowsError(try Command.script("delay 2", timeout: 0.1))
        XCTAssertEqual(try Command.script("return \"ok\"", timeout: 5), "ok")
    }
    func testAilyStatusParsesBuildPreambleAndNestedResponses() {
        XCTAssertEqual(AilyService.parseStatus("build 1\n{\"running\":true}\n"), true)
        XCTAssertEqual(AilyService.parseStatus("{\"daemon\":{\"running\":false}}"), false)
        XCTAssertEqual(AilyService.parseStatus("{\"ok\":true,\"data\":{\"running\":true}}"), true)
        XCTAssertEqual(AilyService.parseStatus("{\"ok\":false,\"error\":{\"code\":\"DAEMON_UNREACHABLE\"}}"), false)
        XCTAssertNil(AilyService.parseStatus("not JSON"))
        XCTAssertNil(AilyService.parseStatus("{\"message\":\"permission denied\"}"))
    }
    func testBatteryLevelsBelongOnlyToTheSelectedDevice() {
        let inventory: [String: Any] = ["devices": [["My AirPods": ["device_address": "AA-BB", "battery_left": "80%", "battery_right": "70%"]], ["Other": ["battery_left": "10%"]]]]
        XCTAssertEqual(BluetoothAudio.batteryValues(inventory, name: "My AirPods", address: "aa:bb"), ["80%", "70%"])
        XCTAssertTrue(BluetoothAudio.batteryValues(inventory, name: "Missing", address: "xx").isEmpty)
    }
    func testCommandUsesLiteralArguments() throws {
        let literal = "$(whoami) `uname` ; echo unsafe"
        XCTAssertEqual(try Command.run("/usr/bin/printf", ["%s", literal]), literal)
    }
    func testCommandDoesNotBlockOnLargeOutput() throws {
        let output = try Command.run("/usr/bin/awk", ["BEGIN { for (i=0; i<20000; i++) print \"abcdefghij\" }"], timeout: 5)
        XCTAssertGreaterThan(output.utf8.count, 200000)
    }
    func testCommandTimeoutAndNonzeroExitAreErrors() {
        let start = Date()
        XCTAssertThrowsError(try Command.run("/bin/sleep", ["10"], timeout: 0.1))
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
        XCTAssertThrowsError(try Command.run("/usr/bin/false", []))
    }
    @MainActor func testTransparentPanelDoesNotAddWindowShadowToGlass() {
        let panel = ControlsPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 519),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        if #available(macOS 26, *) { XCTAssertFalse(panel.hasShadow) }
        else { XCTAssertTrue(panel.hasShadow) }
    }
    @MainActor func testCurrentSystemUsesNativeMaterialAndRowsAreBounded() {
        let store = ControlStore(settings: settings)
        let controller = ControlsViewController(store: store)
        let view = controller.view
        view.setFrameSize(NSSize(width: 360, height: controller.desiredHeight))
        view.layoutSubtreeIfNeeded()
        if #available(macOS 26, *) { XCTAssertTrue(view is NSGlassEffectView) }
        else { XCTAssertTrue(view is NSVisualEffectView) }
        let scroll = descendants(view).compactMap { $0 as? NSScrollView }.first!
        let scrollFrame = view.convert(scroll.bounds, from: scroll)
        XCTAssertEqual(view.bounds.maxY - scrollFrame.maxY, 12, accuracy: 1)
        XCTAssertEqual(scroll.frame.height, 440, accuracy: 1)
        XCTAssertFalse(scroll.hasVerticalScroller)
        settings.visible = Control.all.map(\.id)
        controller.view.layoutSubtreeIfNeeded()
        let nextScroll = descendants(view).compactMap { $0 as? NSScrollView }.first!
        XCTAssertTrue(nextScroll.hasVerticalScroller)
        XCTAssertEqual(nextScroll.frame.height, 440, accuracy: 1)
        XCTAssertEqual(nextScroll.documentView?.subviews.count, 31)
        XCTAssertEqual(controller.desiredHeight, 519)
    }
    @MainActor func testSharedLabelsEnforceMinimumTextSize() {
        XCTAssertEqual(label("Contact", size: 10).font?.pointSize, 14)
        XCTAssertEqual(label("Title", size: 19).font?.pointSize, 19)
        XCTAssertEqual(ActionButton(title: "Settings", handler: {}).font?.pointSize, 14)
    }
    @MainActor func testPreferencesRoutingAndLocalizedControlSearch() throws {
        let controller = PreferencesController(settings: settings)
        let window = try XCTUnwrap(controller.window)
        let list = controller.controls
        _ = list.view
        for english in [false, true] {
            controller.selectPane(1)
            settings.english = english
            XCTAssertEqual(controller.selectedPane, 1)
            let search = try XCTUnwrap(descendants(list.view).compactMap { $0 as? NSSearchField }.first)
            let table = try XCTUnwrap(descendants(list.view).compactMap { $0 as? NSTableView }.first)
            XCTAssertEqual(table.numberOfRows, 31)
            XCTAssertGreaterThanOrEqual(search.font?.pointSize ?? 0, 14)
            XCTAssertEqual(search.placeholderString, english ? "Search controls" : "搜索控制项")
            search.stringValue = "aily"
            list.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            XCTAssertEqual(table.numberOfRows, 1)
            search.stringValue = "no matching control"
            list.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            XCTAssertEqual(table.numberOfRows, 0)
            search.stringValue = ""
            list.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
            XCTAssertEqual(table.numberOfRows, 31)
            controller.selectPane(0)
            XCTAssertEqual(controller.selectedPane, 0)
        }
        window.close()
    }
    @MainActor func testKeepAwakeCreatesAndReleasesRealAssertion() {
        let store = ControlStore(settings: settings)
        let control = Control.all.first { $0.id == "awake" }!
        let enabled = XCTNSNotificationExpectation(name: .controlsChanged, object: store)
        enabled.handler = { _ in store.state("awake").enabled && !store.state("awake").busy }
        store.perform(control, enabled: true, duration: 1800)
        wait(for: [enabled], timeout: 5)
        XCTAssertNotNil(settings.deadlines["awake"])
        let stopped = XCTNSNotificationExpectation(name: .controlsChanged, object: store)
        stopped.handler = { _ in !store.state("awake").enabled && !store.state("awake").busy }
        store.perform(control, enabled: false)
        wait(for: [stopped], timeout: 5)
        XCTAssertNil(settings.deadlines["awake"])
    }
    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
