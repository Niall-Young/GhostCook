import AppKit
import ApplicationServices
import IOBluetooth
import Intents
import Darwin

struct OperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

// Arguments are always passed directly to Process; no shell interpolation.
enum Command {
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20, environment: [String: String]? = nil, acceptedExitCodes: Set<Int32> = [0]) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("onecook-command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let outURL = directory.appendingPathComponent("stdout"), errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let output = try FileHandle(forWritingTo: outURL), errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw OperationError("操作超时，请重试 / Operation timed out")
        }
        let result = String(decoding: try Data(contentsOf: outURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard acceptedExitCodes.contains(process.terminationStatus) else { throw OperationError(error.isEmpty ? "macOS 拒绝了此操作 / macOS rejected the operation" : error) }
        return result
    }
    @discardableResult static func script(_ script: String, timeout: TimeInterval = 20) throws -> String {
        try run("/usr/bin/osascript", ["-e", script], timeout: timeout)
    }
    static func bool(_ domain: String, _ key: String, fallback: Bool = false) -> Bool {
        guard let text = try? run("/usr/bin/defaults", ["read", domain, key], timeout: 3) else { return fallback }
        return ["1", "true", "yes"].contains(text.lowercased())
    }
    static func set(_ domain: String, _ key: String, _ value: Bool) throws {
        _ = try run("/usr/bin/defaults", ["write", domain, key, "-bool", value ? "true" : "false"])
    }
}

enum SystemSettings {
    static func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        open("com.apple.preference.security?Privacy_Accessibility")
    }
}

enum BluetoothAudio {
    static var preferred: IOBluetoothDevice? {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            $0.deviceClassMajor == 4 || ($0.name ?? "").localizedCaseInsensitiveContains("AirPods") || ($0.name ?? "").localizedCaseInsensitiveContains("Beats")
        }
        return devices.sorted(by: { (a: IOBluetoothDevice, b: IOBluetoothDevice) -> Bool in
            if a.isConnected() != b.isConnected() { return a.isConnected() }
            return (a.recentAccessDate() ?? Date.distantPast) > (b.recentAccessDate() ?? Date.distantPast)
        }).first
    }
    static func batterySummary(_ device: IOBluetoothDevice) -> String? {
        guard device.isConnected(), let text = try? Command.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 8), let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let values = batteryValues(value, name: device.name ?? "", address: device.addressString ?? "")
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }
    static func batteryValues(_ value: Any, name: String, address: String) -> [String] {
        func normal(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        func collect(_ value: Any) -> [String] {
            if let dictionary = value as? [String: Any] {
                return dictionary.sorted { $0.key < $1.key }.flatMap { key, value -> [String] in
                    if key.lowercased().contains("battery"), let text = value as? String, text.contains("%") { return [text] }
                    if key.lowercased().contains("battery"), let number = value as? Int, (0...100).contains(number) { return ["\(number)%"] }
                    return collect(value)
                }
            }
            return (value as? [Any] ?? []).flatMap(collect)
        }
        func find(_ value: Any) -> [String] {
            if let dictionary = value as? [String: Any] {
                if let candidate = dictionary["device_address"] as? String, !address.isEmpty, normal(candidate) == normal(address) { return collect(dictionary) }
                for (key, entry) in dictionary {
                    if !name.isEmpty && normal(key) == normal(name) { return collect(entry) }
                    let found = find(entry)
                    if !found.isEmpty { return found }
                }
            }
            for entry in value as? [Any] ?? [] { let found = find(entry); if !found.isEmpty { return found } }
            return []
        }
        return find(value)
    }
    static func setConnected(_ enabled: Bool) throws {
        guard let device = preferred else { throw OperationError("没有已配对的蓝牙耳机 / No paired Bluetooth headphones") }
        let result = enabled ? device.openConnection() : device.closeConnection()
        guard result == kIOReturnSuccess else { throw OperationError("无法连接蓝牙设备（\(result)） / Bluetooth operation failed") }
        guard device.isConnected() == enabled else { throw OperationError("蓝牙设备状态尚未改变，请重试 / Bluetooth state did not change") }
    }
}

// AX operates on the existing system Control Center; identifiers may vary across macOS releases.
enum ControlCenter {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return result
    }
    static func descendants(_ root: AXUIElement, depth: Int = 12, match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(root) { return root }
        guard depth > 0 else { return nil }
        for attr in [kAXChildrenAttribute, kAXWindowsAttribute] {
            let children = value(root, attr) as? [AXUIElement] ?? []
            for child in children {
                if let found = descendants(child, depth: depth - 1, match: match) { return found }
            }
        }
        return nil
    }
    static func identifier(_ element: AXUIElement) -> String { value(element, kAXIdentifierAttribute) as? String ?? "" }
    static func isOn(_ element: AXUIElement) -> Bool { (value(element, kAXValueAttribute) as? NSNumber)?.boolValue ?? false }
    static func set(menu: String, checkbox: String, enabled: Bool, focus: Bool = false) throws {
        guard AXIsProcessTrusted() else { throw OperationError("需要辅助功能权限 / Accessibility permission required") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { throw OperationError("控制中心不可用 / Control Center unavailable") }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar = value(root, kAXMenuBarAttribute), CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { throw OperationError("无法读取控制中心菜单栏 / Cannot read Control Center") }
        let bar = unsafeBitCast(menuBar, to: AXUIElement.self)
        guard let item = descendants(bar, match: { identifier($0) == menu }), AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
            throw OperationError("请先在系统设置中将对应控制项显示在菜单栏 / Show this control in the menu bar first")
        }
        defer { AXUIElementPerformAction(item, kAXPressAction as CFString) }
        var checkboxElement: AXUIElement?
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            checkboxElement = descendants(root) {
                let id = identifier($0)
                return focus && !enabled ? id.hasPrefix("focus-mode-activity-") && isOn($0) : id == checkbox
            }
            if checkboxElement != nil { break }
        }
        // Turning Focus off while already off is successful.
        if focus && !enabled && checkboxElement == nil { return }
        guard let target = checkboxElement else { throw OperationError("未找到系统开关，请在系统设置中操作 / System switch unavailable on this macOS version") }
        if isOn(target) != enabled {
            guard AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else { throw OperationError("macOS 拒绝切换 / macOS rejected the change") }
        }
        Thread.sleep(forTimeInterval: 0.25)
        guard isOn(target) == enabled else { throw OperationError("系统开关未达到目标状态 / System switch did not reach the requested state") }
    }
}

// These optional system clients have no public equivalent. Every selector is checked before use.
// Failure is surfaced as unavailable, rather than presenting an invented state.
enum DisplayFeatures {
    static func client(_ className: String) -> NSObject? {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString(className), let method = class_getClassMethod(cls, NSSelectorFromString("new")) else { return nil }
        typealias New = @convention(c) (AnyClass, Selector) -> AnyObject
        return unsafeBitCast(method_getImplementation(method), to: New.self)(cls, NSSelectorFromString("new")) as? NSObject
    }
    static func bool(_ object: NSObject, _ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return nil }
        typealias Get = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Get.self)(object, selector)
    }
    static func state(_ id: String) -> ControlState {
        guard let object = client(id == "nightShift" ? "CBBlueLightClient" : "CBTrueToneClient"), bool(object, "supported") == true else { return ControlState(available: false, known: false) }
        if id == "trueTone" {
            return ControlState(enabled: bool(object, "enabled") ?? false, available: bool(object, "available") ?? false)
        }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard object.responds(to: selector) else { return ControlState(available: false, known: false) }
        // CoreBrightness's status structure has two leading Boolean fields: active, enabled.
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 16)
        defer { bytes.deallocate() }
        bytes.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
        typealias Read = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let read = unsafeBitCast(object.method(for: selector), to: Read.self)(object, selector, bytes)
        return ControlState(enabled: bytes.load(fromByteOffset: 1, as: UInt8.self) != 0, available: read && bytes.load(fromByteOffset: 32, as: UInt8.self) != 0, known: read)
    }
    static func set(_ id: String, _ enabled: Bool) throws {
        guard state(id).available, let object = client(id == "nightShift" ? "CBBlueLightClient" : "CBTrueToneClient") else { throw OperationError("当前显示器不支持此功能 / Unsupported display") }
        let selector = NSSelectorFromString("setEnabled:")
        guard object.responds(to: selector) else { throw OperationError("系统版本不支持此操作 / Unsupported macOS version") }
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Bool
        guard unsafeBitCast(object.method(for: selector), to: Set.self)(object, selector, enabled) else { throw OperationError("显示器拒绝切换 / Display rejected the change") }
        Thread.sleep(forTimeInterval: 0.2)
        guard state(id).enabled == enabled else { throw OperationError("显示器状态未改变 / Display state did not change") }
    }
}
