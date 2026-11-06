import Foundation

struct Control: Identifiable {
    let id: String
    let symbol: String
    let zh: String
    let en: String
    let detailZH: String
    let detailEN: String
    var isAction: Bool { Self.actions.contains(id) }
    var isTimed: Bool { ["awake", "darkMode", "dnd"].contains(id) }
    var needsConfirmation: Bool { ["xcodeClean", "emptyTrash", "clearDownloads", "quitApps", "ejectDisk"].contains(id) }
    private static let actions: Set<String> = ["screenSaver", "frontApp", "xcodeClean", "emptyTrash", "clearDownloads", "ejectDisk", "clipboard", "hideWindow", "displaySleep", "lockScreen", "quitApps"]
    static let all: [Control] = [
        Control(id: "desktop", symbol: "square.grid.3x3", zh: "隐藏桌面图标", en: "Hide desktop icons", detailZH: "Finder", detailEN: "Finder"),
        Control(id: "darkMode", symbol: "moon.stars", zh: "深色模式", en: "Dark mode", detailZH: "点击开关选择开启时长", detailEN: "Click the switch to choose a duration"),
        Control(id: "awake", symbol: "cup.and.saucer", zh: "保持唤醒", en: "Keep awake", detailZH: "点击开关选择开启时长", detailEN: "Click the switch to choose a duration"),
        Control(id: "airpods", symbol: "headphones", zh: "蓝牙耳机", en: "Bluetooth headphones", detailZH: "自动选择已连接或最近使用的音频设备", detailEN: "Automatically uses the connected or most recent audio device"),
        Control(id: "dnd", symbol: "moon.fill", zh: "专注模式", en: "Focus", detailZH: "点击开关选择开启时长", detailEN: "Click the switch to choose a duration"),
        Control(id: "nightShift", symbol: "moon.haze", zh: "夜览", en: "Night Shift", detailZH: "调暖显示屏色温", detailEN: "Warm the display colours"),
        Control(id: "screenSaver", symbol: "display", zh: "屏幕保护程序", en: "Screen saver", detailZH: "启动安静的屏幕保护", detailEN: "Start a calm screen saver"),
        Control(id: "trueTone", symbol: "sun.max", zh: "原彩显示", en: "True Tone", detailZH: "根据环境光调整显示效果", detailEN: "Match the display to ambient light"),
        Control(id: "frontApp", symbol: "macwindow.on.rectangle", zh: "切换前台应用", en: "Switch front app", detailZH: "将下一个应用带到前台", detailEN: "Bring the next app forward"),
        Control(id: "muteMic", symbol: "mic.slash", zh: "麦克风静音", en: "Mute microphone", detailZH: "取消静音时恢复上次输入音量", detailEN: "Restore the previous input volume when unmuted"),
        Control(id: "xcodeClean", symbol: "paintbrush", zh: "清理 Xcode 缓存", en: "Clean Xcode cache", detailZH: "删除派生数据", detailEN: "Remove derived data"),
        Control(id: "emptyTrash", symbol: "trash", zh: "清空废纸篓", en: "Empty Trash", detailZH: "移除已丢弃的文件", detailEN: "Remove discarded files"),
        Control(id: "clearDownloads", symbol: "folder.badge.minus", zh: "清理下载文件夹", en: "Clear Downloads", detailZH: "将全部内容移到废纸篓", detailEN: "Move all contents to Trash"),
        Control(id: "ejectDisk", symbol: "eject", zh: "推出磁盘", en: "Eject disks", detailZH: "短按全部推出 · 长按保护磁盘", detailEN: "Eject all · hold the switch to protect disks"),
        Control(id: "clipboard", symbol: "clipboard", zh: "清空剪贴板", en: "Clear clipboard", detailZH: "移除已复制的内容", detailEN: "Remove copied content"),
        Control(id: "hideWindow", symbol: "eye.slash", zh: "隐藏窗口", en: "Hide window", detailZH: "隐藏前台应用", detailEN: "Hide the front app"),
        Control(id: "hideDock", symbol: "dock.rectangle", zh: "隐藏 Dock", en: "Hide Dock", detailZH: "显示或隐藏 Dock", detailEN: "Show or hide the Dock"),
        Control(id: "lowPower", symbol: "bolt", zh: "低电量模式", en: "Low power mode", detailZH: "降低 Mac 能耗", detailEN: "Reduce energy use"),
        Control(id: "highPower", symbol: "gauge.with.dots.needle.67percent", zh: "高能耗模式", en: "High Power mode", detailZH: "在支持的 Mac 上提高持续性能", detailEN: "Increase sustained performance on supported Macs"),
        Control(id: "music", symbol: "music.note", zh: "音乐播放", en: "Music playback", detailZH: "播放或暂停当前队列", detailEN: "Play or pause the current queue"),
        Control(id: "spotify", symbol: "waveform", zh: "Spotify 播放", en: "Spotify playback", detailZH: "播放或暂停 Spotify", detailEN: "Play or pause Spotify"),
        Control(id: "hiddenFiles", symbol: "folder", zh: "显示隐藏文件", en: "Show hidden files", detailZH: "在 Finder 中显示文件", detailEN: "Reveal files in Finder"),
        Control(id: "displaySleep", symbol: "display", zh: "显示器休眠", en: "Display sleep", detailZH: "关闭显示屏", detailEN: "Turn the display off"),
        Control(id: "resolution", symbol: "display.and.arrow.down", zh: "屏幕分辨率", en: "Screen resolution", detailZH: "直接在 Onecook 中选择", detailEN: "Choose directly in Onecook"),
        Control(id: "hideWidgets", symbol: "rectangle.3.group", zh: "隐藏桌面小组件", en: "Hide desktop widgets", detailZH: "在普通桌面和台前调度中保持整洁", detailEN: "Keep the desktop clear in every workspace mode"),
        Control(id: "stageManager", symbol: "squares.leading.rectangle", zh: "台前调度", en: "Stage Manager", detailZH: "围绕当前任务整理已打开的窗口", detailEN: "Organise open windows around the current task"),
        Control(id: "cleanScreen", symbol: "eye", zh: "屏幕清洁", en: "Clean screen", detailZH: "长按 Esc 退出", detailEN: "Hold Esc to finish"),
        Control(id: "lockKeyboard", symbol: "keyboard", zh: "键盘清洁", en: "Keyboard cleaning", detailZH: "清洁时忽略键盘输入 · 从菜单关闭", detailEN: "Ignore key presses while cleaning · turn off from the menu"),
        Control(id: "lockScreen", symbol: "lock", zh: "锁定屏幕", en: "Lock screen", detailZH: "需要密码才能继续", detailEN: "Require your password"),
        Control(id: "quitApps", symbol: "rectangle.stack.badge.minus", zh: "关闭其他应用", en: "Quit other apps", detailZH: "保留当前应用、Onecook 与 Finder", detailEN: "Keeps your current app, Onecook and Finder"),
        Control(id: "feishuAily", symbol: "paperplane.fill", zh: "飞书 aily", en: "Feishu aily", detailZH: "启动飞书 aily 后台服务", detailEN: "Starts the aily background service"),
    ]
}

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let display: String
}

final class Settings {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var english: Bool {
        get { defaults.string(forKey: "language") == "en" }
        set { defaults.set(newValue ? "en" : "zh", forKey: "language"); changed() }
    }
    func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    var order: [String] {
        get { Self.normalizedOrder(defaults.stringArray(forKey: "order") ?? []) }
        set { defaults.set(Self.normalizedOrder(newValue), forKey: "order"); changed() }
    }
    var visible: [String] {
        get { Self.validIDs(defaults.stringArray(forKey: "visible") ?? Array(Control.all.prefix(8).map(\.id))) }
        set { defaults.set(Self.validIDs(newValue), forKey: "visible"); changed() }
    }
    var shortcuts: [String: Shortcut] {
        get { read("shortcuts", fallback: [:]) }
        set { write(newValue, key: "shortcuts"); changed() }
    }
    var deadlines: [String: Date] {
        get { (read("deadlines", fallback: [:]) as [String: Date]).filter { id, _ in Control.all.contains { $0.id == id && $0.isTimed } } }
        set { write(newValue, key: "deadlines") }
    }
    var protectedVolumes: [String] {
        get { defaults.stringArray(forKey: "protectedVolumes") ?? [] }
        set { defaults.set(newValue, forKey: "protectedVolumes") }
    }
    var controls: [Control] { order.compactMap { id in Control.all.first { $0.id == id } } }
    var selectedControls: [Control] { controls.filter { visible.contains($0.id) } }
    static func validIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in Control.all.contains { $0.id == id } && seen.insert(id).inserted }
    }
    static func normalizedOrder(_ ids: [String]) -> [String] {
        let valid = validIDs(ids)
        return valid + Control.all.map(\.id).filter { !valid.contains($0) }
    }
    func toggleVisibility(_ id: String) {
        visible = visible.contains(id) ? visible.filter { $0 != id } : visible + [id]
    }
    func move(_ id: String, before target: String?) {
        var values = order.filter { $0 != id }
        let index = target.flatMap { values.firstIndex(of: $0) } ?? values.count
        values.insert(id, at: index)
        order = values
    }
    private func read<T: Decodable>(_ key: String, fallback: T) -> T {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    private func write<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func changed() { NotificationCenter.default.post(name: .settingsChanged, object: self) }
}
extension Notification.Name {
    static let settingsChanged = Notification.Name("Onecook.settingsChanged")
    static let controlsChanged = Notification.Name("Onecook.controlsChanged")
}

struct ControlState {
    var enabled = false
    var available = true
    var known = true
    var busy = false
    var message: String?
}
