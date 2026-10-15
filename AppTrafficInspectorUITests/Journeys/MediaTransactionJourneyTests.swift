import XCTest

@MainActor
final class MediaTransactionJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = UITestEnvironment.launchApp()
    }

    override func tearDown() async throws {
        app.terminate()
        app = nil
        try await super.tearDown()
    }

    func testOpenSeededImageTransaction() {
        let browser = TrafficBrowserScreen(app: app)
        browser.openSeededImageTransaction()
        browser.assertImagePreviewIsVisible()
    }

    func testInspectMultipartUploadAndCopyCurl() {
        let browser = TrafficBrowserScreen(app: app)
        browser.openSeededUploadTransaction()
        browser.assertMultipartUploadIsVisible()
        browser.copyCurl()
        browser.assertCurlCopiedWithExportedFile()
    }

    func testReplayOpensComparison() {
        let browser = TrafficBrowserScreen(app: app)
        browser.openSeededReplayTransaction()
        browser.assertReplayComparisonIsVisible()
    }

}
