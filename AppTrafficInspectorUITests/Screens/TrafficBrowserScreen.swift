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
        XCTAssertTrue(projectRow.waitForExistence(timeout: UITestEnvironment.timeout))
        projectRow.tap()
        XCTAssertTrue(deviceRow.waitForExistence(timeout: UITestEnvironment.timeout))
        deviceRow.tap()
        XCTAssertTrue(imageTransactionRow.waitForExistence(timeout: UITestEnvironment.timeout))
        imageTransactionRow.tap()
    }

    func assertImagePreviewIsVisible() {
        let preview = app.descendants(matching: .any)
            .matching(identifier: "media-preview-image")
            .firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: UITestEnvironment.timeout))
    }
}
