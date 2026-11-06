import XCTest
@testable import Onecook

final class UpdateTests: XCTestCase {
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

    private static func response(_ body: String, path: String, status: Int = 200) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: URL(string: "https://github.com/Niall-Young/GhostCook" + path)!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
