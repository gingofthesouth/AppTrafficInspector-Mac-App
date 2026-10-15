import XCTest

@MainActor
enum UITestEnvironment {
    static let timeout: TimeInterval = 8

    static func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        return app
    }
}
