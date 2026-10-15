#if DEBUG
import Foundation

enum UITestConfiguration {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }
}

@MainActor
enum UITestSupport {
    static func configure() {
        guard UITestConfiguration.isUITesting else { return }

        UserDefaults.standard.set(false, forKey: "mcpServerEnabled")
        let controller = AppTrafficController.shared
        controller.publisher.stopPublishing()
        controller.projects.removeAll()
        controller.selectedProject = nil

        addTransaction(
            id: "ui-json-transaction",
            url: "https://example.com/profile",
            statusCode: 200,
            contentType: "application/json",
            response: Data(#"{"name":"UI Test"}"#.utf8)
        )
        addTransaction(
            id: "ui-image-transaction",
            url: "https://example.com/avatar.png",
            statusCode: 200,
            contentType: "image/png",
            response: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") ?? Data()
        )
    }

    private static func addTransaction(
        id: String,
        url: String,
        statusCode: Int,
        contentType: String,
        response: Data
    ) {
        let object: [String: Any] = [
            "packetId": id,
            "requestInfo": [
                "url": url,
                "requestMethod": "GET",
                "statusCode": statusCode,
                "responseHeaders": ["Content-Type": contentType],
                "responseData": response.base64EncodedString()
            ],
            "project": ["projectName": "UI Test Project"],
            "device": [
                "deviceId": "ui-test-device",
                "deviceName": "UI Test Device",
                "deviceDescription": "Deterministic UI fixture"
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let transaction = try? JSONDecoder().decode(AppTrafficPacket.self, from: data)
        else {
            return
        }
        AppTrafficController.shared.didGetPacket(
            publisher: AppTrafficController.shared.publisher,
            packet: transaction
        )
    }
}
#endif
