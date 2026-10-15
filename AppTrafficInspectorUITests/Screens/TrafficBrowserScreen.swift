import XCTest

@MainActor
struct TrafficBrowserScreen {
    let app: XCUIApplication

    private var projectRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "project-row-UI Test Project")
            .firstMatch
    }

    private var deviceRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "device-row-ui-test-device")
            .firstMatch
    }

    private var imageTransactionRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "transaction-row-ui-image-transaction")
            .firstMatch
    }

    func openSeededImageTransaction() {
        openTransaction(imageTransactionRow)
    }

    func openSeededUploadTransaction() {
        openTransaction(element("transaction-row-ui-upload-transaction"))
    }

    func openSeededReplayTransaction() {
        openTransaction(element("transaction-row-ui-replay-transaction"))
    }

    private func openTransaction(_ row: XCUIElement) {
        XCTAssertTrue(projectRow.waitForExistence(timeout: UITestEnvironment.timeout))
        projectRow.click()
        XCTAssertTrue(deviceRow.waitForExistence(timeout: UITestEnvironment.timeout))
        deviceRow.click()
        XCTAssertTrue(row.waitForExistence(timeout: UITestEnvironment.timeout))
        row.click()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func assertMultipartUploadIsVisible() {
        XCTAssertTrue(element("multipart-parts").waitForExistence(timeout: UITestEnvironment.timeout))
        XCTAssertTrue(element("multipart-part-photo").exists)
        XCTAssertTrue(element("media-preview-image").exists)
    }

    func copyCurl() {
        let button = element("copy-curl-button")
        XCTAssertTrue(button.waitForExistence(timeout: UITestEnvironment.timeout))
        button.click()
    }

    func assertCurlCopiedWithExportedFile() {
        let notice = element("copied-notice")
        XCTAssertTrue(notice.waitForExistence(timeout: UITestEnvironment.timeout))
        let text = (notice.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? notice.label
        XCTAssertTrue(text.contains("1 body file"), "Unexpected notice: \(text)")
    }

    func assertReplayComparisonIsVisible() {
        XCTAssertTrue(element("replay-banner").waitForExistence(timeout: UITestEnvironment.timeout))
        XCTAssertTrue(element("replay-body-equality").waitForExistence(timeout: UITestEnvironment.timeout))
        XCTAssertFalse(element("replay-original-missing").exists)
        XCTAssertTrue(element("replay-compare").exists)
    }

    func assertImagePreviewIsVisible() {
        let preview = app.descendants(matching: .any)
            .matching(identifier: "media-preview-image")
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: UITestEnvironment.timeout))
    }
}
