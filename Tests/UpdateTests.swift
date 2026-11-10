import XCTest
@testable import Onecook

final class UpdateTests: XCTestCase {
    @MainActor func testCancelledShutdownCannotTerminateALaterAttempt() async {
        let suite = "dev.nialyoung.onecook.tests.shutdown." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ControlStore(settings: Settings(defaults: defaults))
        let stale = expectation(description: "Cancelled shutdown must not reply")
        stale.isInverted = true
        store.shutdown { stale.fulfill() }
        store.resumeAfterCancelledShutdown()
        let retried = expectation(description: "A fresh shutdown still completes")
        store.shutdown { retried.fulfill() }
        await fulfillment(of: [stale, retried], timeout: 0.5)
    }

    @MainActor func testHelperFailureStopsSpinnerAndAllowsRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let failure = root.appendingPathComponent("failure.txt")
        try "退出超时，更新已取消".write(to: failure, atomically: true, encoding: .utf8)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        try helper.run()
        let checker = UpdateChecker(service: ReleaseService(fetch: { _ in
            Self.response("", path: "/releases/tag/v0.1.0")
        }))
        let cancelled = expectation(description: "Pending termination cancelled")
        checker.monitorInstallation(helper, failure: failure) { cancelled.fulfill() }
        XCTAssertTrue(checker.busy)
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertEqual(checker.state, .installFailed("退出超时，更新已取消"))
        XCTAssertFalse(checker.busy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failure.path))
        await checker.check()
        XCTAssertEqual(checker.state, .current)
    }

    func testHelperExitTimeoutKeepsOriginalAndRemovesStaging() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("GhostCook.app")
        let work = root.appendingPathComponent("work")
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        let marker = target.appendingPathComponent("version")
        try "old".write(to: marker, atomically: true, encoding: .utf8)
        let script = root.appendingPathComponent("helper.sh")
        try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)
        let failure = root.appendingPathComponent("failure.txt")
        // The test host remains alive; a one-iteration limit avoids real waits.
        XCTAssertThrowsError(try UpdateInstaller.run("/bin/sh", [script.path, target.path,
            work.appendingPathComponent("GhostCook.app").path, work.path,
            String(ProcessInfo.processInfo.processIdentifier), failure.path, "/usr/bin/true", "1"]))
        XCTAssertEqual(try String(contentsOf: marker), "old")
        XCTAssertTrue(try String(contentsOf: failure).contains("更新已取消"))
        XCTAssertFalse(fm.fileExists(atPath: work.path))
    }

    func testUpdateTerminationFromSwiftTaskExits() throws {
        let executable = try XCTUnwrap(Bundle.main.executableURL)
        let environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("XCInject") && !$0.key.hasPrefix("DYLD_")
        }
        // A child app runs the real terminateLater/shutdown handshake, without
        // touching user preferences, timers, Trash, Downloads or other apps.
        for mode in ["--test-update-shutdown", "--test-update-shutdown-failure"] {
            _ = try Command.run(executable.path, [mode], timeout: 10, environment: environment)
        }
    }

    func testNumericVersions() throws {
        XCTAssertEqual(ReleaseVersion("v1.2"), ReleaseVersion("1.2.0"))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("0.9.9")), try XCTUnwrap(ReleaseVersion("0.10.0")))
        for invalid in ["", "v", "1..0", "1.2-beta", "1.2+3", "GhostCook-1.0", "1.2/other"] {
            XCTAssertNil(ReleaseVersion(invalid), invalid)
        }
    }

    func testOnlySafeCompatibleInstallersAreSelected() {
        let prefix = "/Niall-Young/GhostCook/releases/download/v1.0.0/"
        let html = """
        <a href="https://example.com\(prefix)Fake.dmg">fake</a>
        <a href="\(prefix)GhostCook-windows.zip">windows</a>
        <a href="\(prefix)GhostCook-arm64.zip.sig">signature</a>
        <a href="\(prefix)GhostCook-x86_64.dmg">intel</a>
        <a href="\(prefix)GhostCook-arm64.zip">arm</a>
        """
        XCTAssertEqual(ReleaseService.downloadURL(html: html, tag: "v1.0.0", architecture: "arm64")?.lastPathComponent, "GhostCook-arm64.zip")
        XCTAssertEqual(ReleaseService.downloadURL(html: html, tag: "v1.0.0", architecture: "x86_64")?.lastPathComponent, "GhostCook-x86_64.dmg")
        XCTAssertNil(ReleaseService.downloadURL(html: html, tag: "v2.0.0"))
        XCTAssertNil(ReleaseService.downloadURL(html: "<a href='\(prefix)GhostCook-x64.dmg'>intel</a>", tag: "v1.0.0", architecture: "arm64"))
    }

    func testLatestReleaseAndAssetResolution() async throws {
        let service = ReleaseService(fetch: { url in
            if url.path.hasSuffix("/latest") {
                return Self.response("", path: "/releases/tag/v0.10.0")
            }
            XCTAssertEqual(url.path, "/Niall-Young/GhostCook/releases/expanded_assets/v0.10.0")
            return Self.response("<a href='/Niall-Young/GhostCook/releases/download/v0.10.0/GhostCook-universal.dmg'>download</a>", path: "/releases/expanded_assets/v0.10.0")
        })
        let release = try await service.latest(currentVersion: "0.9.0")
        XCTAssertEqual(release?.tag, "v0.10.0")
        XCTAssertEqual(release?.download?.lastPathComponent, "GhostCook-universal.dmg")
    }

    @MainActor func testEmptyRepositoryAndFailuresDoNotReportUpToDate() async {
        let empty = UpdateChecker(service: ReleaseService(fetch: { _ in Self.response("There aren’t any releases here", path: "/releases") }))
        await empty.check()
        XCTAssertEqual(empty.state, .noRelease)
        for status in [403, 404, 429, 500] {
            let checker = UpdateChecker(service: ReleaseService(fetch: { _ in Self.response("", path: "/releases", status: status) }))
            await checker.check()
            XCTAssertEqual(checker.state, .failed)
        }
        let invalid = UpdateChecker(service: ReleaseService(fetch: { _ in Self.response("Sign in", path: "/login") }))
        await invalid.check()
        XCTAssertEqual(invalid.state, .failed)
    }

    @MainActor func testSameOrOlderReleaseAndRetry() async {
        for tag in ["v0.1.0", "v0.0.9"] {
            let checker = UpdateChecker(currentVersion: "0.1.0", service: ReleaseService(fetch: { url in
                XCTAssertTrue(url.path.hasSuffix("/latest"))
                return Self.response("", path: "/releases/tag/" + tag)
            }))
            await checker.check()
            XCTAssertEqual(checker.state, .current)
            await checker.check()
            XCTAssertEqual(checker.state, .current)
        }
    }

    func testZipPreferredAndPackageInstallerExcluded() {
        let prefix = "/Niall-Young/GhostCook/releases/download/v1.0.2/"
        let html = ["GhostCook-universal.dmg", "GhostCook-universal.zip", "GhostCook.pkg"]
            .map { "<a href='\(prefix)\($0)'>download</a>" }.joined()
        XCTAssertEqual(ReleaseService.downloadURL(html: html, tag: "v1.0.2")?.pathExtension, "zip")
        XCTAssertNil(ReleaseService.downloadURL(html: "<a href='\(prefix)GhostCook.pkg'>pkg</a>", tag: "v1.0.2"))
    }

    func testSigningRequirementAcceptsDeveloperIDSignedHost() throws {
        try UpdateInstaller.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + UpdateInstaller.signingRequirement, Bundle.main.bundleURL.path])
    }

    func testInstallerRejectsMismatchedOrUnsignedApps() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("GhostCook.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "dev.nialyoung.onecook", "CFBundleShortVersionString": "1.0.2", "CFBundleExecutable": "GhostCook"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = macOS.appendingPathComponent("GhostCook")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        for tag in ["v1.0.3", "v1.0.2"] {
            let release = AvailableRelease(tag: tag, page: ReleaseService.repository, download: nil)
            XCTAssertThrowsError(try UpdateInstaller.validate(app, release: release))
        }
    }

    func testHelperReplacesAndRollsBackWithoutTouchingInstalledApps() throws {
        for mode in ["success", "missing-stage", "launch-failure"] {
            let fm = FileManager.default
            // Spaces, quotes, dollar signs and Unicode must survive positional arguments.
            let root = fm.temporaryDirectory.appendingPathComponent("更新 ' $ " + UUID().uuidString)
            defer { try? fm.removeItem(at: root) }
            let work = root.appendingPathComponent("work")
            let target = root.appendingPathComponent("GhostCook.app")
            let staged = work.appendingPathComponent("GhostCook.app")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            try "old".write(to: target.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            if mode != "missing-stage" {
                try fm.createDirectory(at: staged, withIntermediateDirectories: false)
                try "new".write(to: staged.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            }
            let script = root.appendingPathComponent("helper.sh")
            try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)
            let failure = root.appendingPathComponent("failure.txt")
            let arguments = [script.path, target.path, staged.path, work.path, "2147483647", failure.path,
                             mode == "launch-failure" ? "/usr/bin/false" : "/usr/bin/true"]
            if mode == "success" { try UpdateInstaller.run("/bin/sh", arguments) }
            else { XCTAssertThrowsError(try UpdateInstaller.run("/bin/sh", arguments)) }
            XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("version")), mode == "success" ? "new" : "old")
            XCTAssertEqual(fm.fileExists(atPath: failure.path), mode != "success")
            if mode == "success" { XCTAssertFalse(fm.fileExists(atPath: work.path)) }
        }
    }

    private static func response(_ body: String, path: String, status: Int = 200) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://github.com/Niall-Young/GhostCook" + path)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
