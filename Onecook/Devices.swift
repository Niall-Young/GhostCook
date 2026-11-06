import AppKit
import CoreGraphics

struct Volume {
    let url: URL
    let name: String
    let id: String
}
enum Volumes {
    static func inventory() -> [Volume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeUUIDStringKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsEjectable == true || values.volumeIsRemovable == true else { return nil }
            return Volume(url: url, name: values.volumeName ?? url.lastPathComponent, id: values.volumeUUIDString ?? url.path)
        }
    }
    static func eject(excluding protected: [String]) throws {
        let volumes = inventory().filter { !protected.contains($0.id) }
        for volume in volumes { _ = try Command.run("/usr/sbin/diskutil", ["eject", volume.url.path]) }
    }
}

struct DisplayModeChoice {
    let display: CGDirectDisplayID
    let mode: CGDisplayMode
    var title: String {
        let hidpi = mode.pixelWidth > mode.width ? " · HiDPI" : ""
        let hz = mode.refreshRate > 0 ? " · \(Int(mode.refreshRate.rounded())) Hz" : ""
        return "\(mode.width) × \(mode.height)\(hidpi)\(hz)"
    }
}
enum Displays {
    static func choices(for display: CGDirectDisplayID) -> [DisplayModeChoice] {
        guard let modes = CGDisplayCopyAllDisplayModes(display, [kCGDisplayShowDuplicateLowResolutionModes: false] as CFDictionary) as? [CGDisplayMode] else { return [] }
        var seen = Set<String>()
        return modes.filter { mode in
            guard mode.width >= 640, mode.height >= 480 else { return false }
            return seen.insert("\(mode.width)-\(mode.height)-\(mode.pixelWidth)-\(Int(mode.refreshRate))").inserted
        }.sorted { $0.width == $1.width ? $0.height < $1.height : $0.width < $1.width }.map { DisplayModeChoice(display: display, mode: $0) }
    }
    static func set(_ choice: DisplayModeChoice) throws {
        let result = CGDisplaySetDisplayMode(choice.display, choice.mode, nil)
        guard result == .success else { throw OperationError("无法切换分辨率（\(result.rawValue)） / Cannot change resolution") }
        guard CGDisplayCopyDisplayMode(choice.display)?.ioDisplayModeID == choice.mode.ioDisplayModeID else { throw OperationError("显示器未应用分辨率 / Display did not apply the resolution") }
    }
}
