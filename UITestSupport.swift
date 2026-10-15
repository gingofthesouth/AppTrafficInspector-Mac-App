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
            response: pixelPNG
        )

        let boundary = "UITestBoundary"
        var upload = Data()
        upload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\nHoliday\r\n".utf8))
        upload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"pixel.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        upload.append(pixelPNG)
        upload.append(Data("\r\n--\(boundary)--\r\n".utf8))
        addTransaction(
            id: "ui-upload-transaction",
            url: "https://example.com/photos",
            method: "POST",
            statusCode: 201,
            contentType: "application/json",
            response: Data(#"{"id":42}"#.utf8),
            requestHeaders: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            requestBody: upload
        )

        addTransaction(
            id: "ui-replay-transaction",
            url: "https://example.com/profile",
            statusCode: 200,
            contentType: "application/json",
            response: Data(#"{"name":"UI Test v2"}"#.utf8),
            replayOf: "ui-json-transaction"
        )
    }

    private static let pixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") ?? Data()

    private static func addTransaction(
        id: String,
        url: String,
        method: String = "GET",
        statusCode: Int,
        contentType: String,
        response: Data,
        requestHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        replayOf: String? = nil
    ) {
        var requestInfo: [String: Any] = [
            "url": url,
            "requestMethod": method,
            "statusCode": statusCode,
            "requestHeaders": requestHeaders,
            "responseHeaders": ["Content-Type": contentType],
            "responseData": response.base64EncodedString()
        ]
        if let requestBody { requestInfo["requestBody"] = requestBody.base64EncodedString() }
        let object: [String: Any] = [
            "packetId": id,
            "requestInfo": requestInfo,
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
        transaction.replayOfPacketId = replayOf
        AppTrafficController.shared.ingest(transaction)
    }
}
#endif
