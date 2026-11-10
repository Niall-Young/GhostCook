import AppKit
import IOKit.pwr_mgt
import Intents

final class ControlStore {
    let settings: Settings
    let cleaning = CleaningController()
    private let pasteboard: NSPasteboard
    private let cleanupQueue = DispatchQueue(label: "dev.nialyoung.onecook.cleanup", qos: .userInitiated)
    private let queue = DispatchQueue(label: "dev.nialyoung.onecook.operations", qos: .userInitiated)
    private(set) var states: [String: ControlState] = [:]
    private var assertion: IOPMAssertionID = 0
    private var refreshInProgress = false
    private var timer: Timer?
    private var focusAuthorizationRequested = false
    private var retryAfter: [String: Date] = [:]
    private(set) var audioDeviceName: String?
    private(set) var audioBattery: String?
    private var lastBatteryRead = Date.distantPast
    private var cachedBattery: String?
    var previousApp: NSRunningApplication?
    var onError: ((Control, Error) -> Void)?
    var onBeforeExternalUI: (() -> Void)?
    init(settings: Settings, pasteboard: NSPasteboard = .general) {
        self.settings = settings
        self.pasteboard = pasteboard
        for control in Control.all { states[control.id] = ControlState(known: control.isAction) }
        cleaning.onScreenStopped = { [weak self] in self?.states["cleanScreen"]?.enabled = false; self?.changed() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func state(_ id: String) -> ControlState { states[id] ?? ControlState() }
    func changed() { NotificationCenter.default.post(name: .controlsChanged, object: self) }
    @objc private func wake() { refresh(); tick() }
    func refresh() {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        queue.async {
            let snapshot = self.snapshot(awake: self.assertion != 0)
            DispatchQueue.main.async {
                for (id, value) in snapshot where self.states[id]?.busy != true {
                    var next = value
                    if !next.known { next.enabled = self.states[id]?.enabled ?? false }
                    next.message = self.states[id]?.message
                    self.states[id] = next
                }
                self.refreshInProgress = false
                self.changed()
            }
        }
    }
    private func snapshot(awake: Bool) -> [String: ControlState] {
        var result: [String: ControlState] = [:]
        func add(_ id: String, _ enabled: Bool, available: Bool = true, known: Bool = true) { result[id] = ControlState(enabled: enabled, available: available, known: known) }
        add("desktop", !Command.bool("com.apple.finder", "CreateDesktop", fallback: true))
        let dark = (try? Command.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"], timeout: 3)) == "Dark"
        add("darkMode", dark)
        add("awake", awake)
        add("hideDock", Command.bool("com.apple.dock", "autohide"))
        add("hiddenFiles", Command.bool("com.apple.finder", "AppleShowAllFiles"))
        add("hideWidgets", Command.bool("com.apple.WindowManager", "StandardHideWidgets") && Command.bool("com.apple.WindowManager", "StageManagerHideWidgets"))
        add("stageManager", Command.bool("com.apple.WindowManager", "GloballyEnabled"))
        add("lowPower", ProcessInfo.processInfo.isLowPowerModeEnabled)
        let power = (try? Command.run("/usr/bin/pmset", ["-g", "custom"], timeout: 3)) ?? ""
        let highPowerSupported = power.range(of: #"(?m)^\s*(highpowermode|powermode)\s+"#, options: .regularExpression) != nil
        add("highPower", power.range(of: #"(?m)^\s*(highpowermode\s+1|powermode\s+2)"#, options: .regularExpression) != nil, available: highPowerSupported, known: highPowerSupported)
        let volume = try? Command.script("input volume of (get volume settings)")
        add("muteMic", volume == "0", known: volume != nil)
        let device = BluetoothAudio.preferred
        add("airpods", device?.isConnected() ?? false, available: device != nil)
        if Date().timeIntervalSince(lastBatteryRead) > 60 {
            cachedBattery = device.flatMap { BluetoothAudio.batterySummary($0) }
            lastBatteryRead = Date()
        }
        let name = device?.name, battery = cachedBattery
        DispatchQueue.main.async { self.audioDeviceName = name; self.audioBattery = battery }

        for id in ["nightShift", "trueTone"] { result[id] = DisplayFeatures.state(id) }
        let focus = INFocusStatusCenter.default
        let focused = focus.authorizationStatus == .authorized ? focus.focusStatus.isFocused : nil
        add("dnd", focused ?? false, known: focused != nil)
        for (id, bundle, name) in [("music", "com.apple.Music", "Music"), ("spotify", "com.spotify.client", "Spotify")] {
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
            let playing = running ? try? Command.script("tell application \"\(name)\" to get player state as string") : "stopped"
            add(id, playing == "playing", available: installed, known: playing != nil)
        }
        let aily = AilyService.status()
        add("feishuAily", aily ?? false, available: AilyService.installed, known: aily != nil)
        return result
    }
    func perform(_ control: Control, enabled: Bool? = nil, duration: TimeInterval? = nil) {
        guard !state(control.id).busy else { return }
        if control.id == "dnd", !focusAuthorizationRequested, INFocusStatusCenter.default.authorizationStatus == .notDetermined {
            focusAuthorizationRequested = true
            INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async { self?.perform(control, enabled: enabled, duration: duration) }
            }
            return
        }
        let target = enabled ?? !state(control.id).enabled
        states[control.id]?.busy = true
        states[control.id]?.message = nil
        states[control.id]?.completedAt = nil
        changed()
        let front = previousApp
        let protected = settings.protectedVolumes
        if ["dnd", "lowPower", "highPower", "frontApp", "hideWindow", "lockScreen", "cleanScreen"].contains(control.id) { onBeforeExternalUI?() }
        if ["cleanScreen", "lockKeyboard", "clipboard", "frontApp", "hideWindow", "quitApps"].contains(control.id) {
            do {
                switch control.id {
                case "cleanScreen": cleaning.setScreen(target, settings: settings)
                case "lockKeyboard": try cleaning.setKeyboard(target)
                case "clipboard":
                    pasteboard.clearContents()
                    guard pasteboard.types?.isEmpty ?? true else {
                        throw OperationError("剪贴板未能清空，请重试 / Could not clear the clipboard; try again")
                    }
                case "frontApp":
                    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() && $0 != front }
                    _ = apps.first?.activate(options: .activateIgnoringOtherApps)
                case "hideWindow": _ = front?.hide()
                case "quitApps":
                    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() && app != front && app.bundleIdentifier != "com.apple.finder" { app.terminate() }
                default: break
                }
                complete(control, enabled: target, duration: duration, error: nil)
            } catch { complete(control, enabled: target, duration: nil, error: error) }
            return
        }
        let operationQueue = ["emptyTrash", "clearDownloads", "xcodeClean"].contains(control.id) ? cleanupQueue : queue
        operationQueue.async {
            do {
                try self.execute(control.id, enabled: target, protected: protected)
                DispatchQueue.main.async { self.complete(control, enabled: target, duration: duration, error: nil) }
            } catch { DispatchQueue.main.async { self.complete(control, enabled: target, duration: nil, error: error) } }
        }
    }
    private func complete(_ control: Control, enabled: Bool, duration: TimeInterval?, error: Error?) {
        states[control.id]?.busy = false
        if let error {
            states[control.id]?.message = error.localizedDescription
            if settings.deadlines[control.id] != nil { retryAfter[control.id] = Date().addingTimeInterval(60) }
            onError?(control, error)
        } else {
            states[control.id]?.enabled = control.isAction ? false : enabled
            states[control.id]?.known = true
            if control.isTimed {
                if enabled, let duration { settings.deadlines[control.id] = Date().addingTimeInterval(duration) }
                else { settings.deadlines.removeValue(forKey: control.id) }
                retryAfter.removeValue(forKey: control.id)
            }
            if control.isAction {
                let completedAt = Date()
                states[control.id]?.completedAt = completedAt
                states[control.id]?.message = settings.text("已完成", "Completed")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.states[control.id]?.completedAt == completedAt else { return }
                    self.states[control.id]?.completedAt = nil
                    self.states[control.id]?.message = nil
                    self.changed()
                }
            }
        }
        changed()
    }
    private func execute(_ id: String, enabled: Bool, protected: [String]) throws {
        let literal = enabled ? "true" : "false"
        switch id {
        case "awake":
            if enabled && assertion == 0 {
                var value: IOPMAssertionID = 0
                let code = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "GhostCook keep awake" as CFString, &value)
                guard code == kIOReturnSuccess else { throw OperationError("无法保持唤醒 / Cannot prevent sleep") }
                assertion = value
            } else if !enabled && assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        case "desktop": try Command.set("com.apple.finder", "CreateDesktop", !enabled); _ = try? Command.run("/usr/bin/killall", ["Finder"])
        case "darkMode": try Command.script("tell application \"System Events\" to tell appearance preferences to set dark mode to \(literal)")
        case "hideDock": try Command.set("com.apple.dock", "autohide", enabled); _ = try Command.run("/usr/bin/killall", ["Dock"])
        case "hiddenFiles": try Command.set("com.apple.finder", "AppleShowAllFiles", enabled); _ = try? Command.run("/usr/bin/killall", ["Finder"])
        case "hideWidgets":
            try Command.set("com.apple.WindowManager", "StandardHideWidgets", enabled)
            try Command.set("com.apple.WindowManager", "StageManagerHideWidgets", enabled)
            _ = try Command.run("/usr/bin/killall", ["Dock"])
        case "stageManager": try Command.set("com.apple.WindowManager", "GloballyEnabled", enabled); _ = try Command.run("/usr/bin/killall", ["Dock"])
        case "muteMic":
            if enabled, let value = Int(try Command.script("input volume of (get volume settings)")), value > 0 { settings.defaults.set(value, forKey: "previousInputVolume") }
            let saved = settings.defaults.integer(forKey: "previousInputVolume")
            try Command.script("set volume input volume \(enabled ? 0 : (saved > 0 ? saved : 50))")
            if !enabled { settings.defaults.removeObject(forKey: "previousInputVolume") }
        case "airpods": try BluetoothAudio.setConnected(enabled)
        case "nightShift", "trueTone": try DisplayFeatures.set(id, enabled)
        case "dnd": try ControlCenter.set(menu: "com.apple.menuextra.focusmode", checkbox: "focus-mode-activity-com.apple.donotdisturb.mode.default", enabled: enabled, focus: true)
        case "lowPower", "highPower": try ControlCenter.set(menu: "com.apple.menuextra.battery", checkbox: id == "lowPower" ? "energy-mode-low" : "energy-mode-high", enabled: enabled)
        case "music", "spotify": try Command.script("tell application \"\(id == "music" ? "Music" : "Spotify")\" to \(enabled ? "play" : "pause")")
        case "screenSaver": _ = try Command.run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case "displaySleep": _ = try Command.run("/usr/bin/pmset", ["displaysleepnow"])
        case "lockScreen": try Command.script("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
        case "emptyTrash": try Command.script("with timeout of 3600 seconds\ntell application \"Finder\" to empty trash\nend timeout", timeout: 3610)
        case "clearDownloads", "xcodeClean":
            let directory = id == "clearDownloads" ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first! : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            if FileManager.default.fileExists(atPath: directory.path) {
                for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) { try FileManager.default.trashItem(at: item, resultingItemURL: nil) }
            }
        case "ejectDisk": try Volumes.eject(excluding: protected)
        case "feishuAily": try AilyService.set(enabled)
        default: throw OperationError("无法执行此控制项 / Unsupported control")
        }
    }
    private func tick() {
        let now = Date()
        for (id, deadline) in settings.deadlines where deadline <= now && (retryAfter[id] ?? .distantPast) <= now && !state(id).busy {
            if let control = Control.all.first(where: { $0.id == id }) { perform(control, enabled: false) }
        }
        if !settings.deadlines.isEmpty { changed() }
    }
    func shutdown(completion: @escaping () -> Void) {
        timer?.invalidate()
        cleaning.stopAll()
        let timedIDs = Array(settings.deadlines.keys)
        queue.async {
            var failed: [String: Date] = [:]
            for id in timedIDs {
                do { try self.execute(id, enabled: false, protected: []) }
                catch { failed[id] = Date() }
            }
            if self.assertion != 0 { IOPMAssertionRelease(self.assertion); self.assertion = 0 }
            // terminate() can run a nested AppKit event loop while a main-queue
            // Swift task is still on the stack. That loop cannot re-enter the
            // main dispatch queue, so deliver the reply through the run loop.
            RunLoop.main.perform(inModes: [.common]) { self.settings.deadlines = failed; completion() }
        }
    }
}
