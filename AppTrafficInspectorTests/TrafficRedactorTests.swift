//
//  TrafficRedactorTests.swift
//  AppTrafficInspectorTests
//

@testable import App_Traffic_Inspector
import Foundation
import Testing

struct TrafficRedactorTests {

    @Test("Header redaction in strict mode redacts Authorization")
    func headerRedactionStrict() {
        let headers = ["Authorization": "Bearer secret", "Content-Type": "application/json"]
        let result = TrafficRedactor.redact(headers: headers, mode: .strict)
        #expect(result["Authorization"] == "[REDACTED — MCP privacy mode]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("Header redaction in moderate mode redacts Authorization")
    func headerRedactionModerate() {
        let headers = ["Authorization": "Bearer secret"]
        let result = TrafficRedactor.redact(headers: headers, mode: .moderate)
        #expect(result["Authorization"] == "[REDACTED — MCP privacy mode]")
    }

    @Test("Header redaction in off mode passes through")
    func headerRedactionOff() {
        let headers = ["Authorization": "Bearer secret"]
        let result = TrafficRedactor.redact(headers: headers, mode: .off)
        #expect(result["Authorization"] == "Bearer secret")
    }

    @Test("URL parameter redaction in strict mode")
    func urlRedactionStrict() {
        let url = "https://api.example.com?api_key=abc123&foo=bar"
        let result = TrafficRedactor.redactURL(urlString: url, mode: .strict)
        #expect(
            (result?.contains("api_key=[REDACTED]") ?? false)
            || (result?.contains("api_key=%5BREDACTED%5D") ?? false)
        )
    }

    @Test("Body pattern redaction redacts Bearer token")
    func bodyRedactionBearer() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xxx"
        let result = TrafficRedactor.redactBody(text: text, mode: .strict)
        #expect(result?.contains("Bearer [REDACTED]") ?? false)
    }

    @Test("JSON field redaction redacts password key")
    func jsonFieldRedaction() {
        let json = #"{"user":"alice","password":"secret123"}"#
        let data = json.data(using: .utf8)
        let result = TrafficRedactor.redactJSONFields(data: data, mode: .strict)
        let redactedJSON = result.flatMap { String(data: $0, encoding: .utf8) }
        #expect(!(redactedJSON?.contains("secret123") ?? false))
        #expect(redactedJSON?.contains("[REDACTED]") ?? false)
    }

    @Test("MCP parser rejects negative content length")
    func parserRejectsNegativeContentLength() {
        var request = Data("POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n".utf8)
        #expect(throws: MCPHTTPParser.ParseError.self) {
            _ = try MCPHTTPParser.parseRequest(&request)
        }
    }

    @Test("MCP parser rejects a body larger than 2 MiB")
    func parserRejectsOversizedBody() {
        let oversizedCount = 2 * 1024 * 1024 + 1
        var request = Data("POST /mcp HTTP/1.1\r\nContent-Length: \(oversizedCount)\r\n\r\n".utf8)
        request.append(Data(repeating: 0x61, count: oversizedCount))
        #expect(throws: MCPHTTPParser.ParseError.self) {
            _ = try MCPHTTPParser.parseRequest(&request)
        }
    }

    @Test("MCP parser rejects oversized headers")
    func parserRejectsOversizedHeaders() {
        let oversizedHeader = String(repeating: "a", count: 65 * 1024)
        var request = Data("POST /mcp HTTP/1.1\r\nX-Oversized: \(oversizedHeader)\r\n\r\n".utf8)
        #expect(throws: MCPHTTPParser.ParseError.self) {
            _ = try MCPHTTPParser.parseRequest(&request)
        }
    }

    @Test("Device retains the newest 1,000 transactions")
    @MainActor
    func transactionCountRetention() {
        let device = AppTrafficDevice()
        for index in 0...1_000 {
            let packet = AppTrafficPacket()
            packet.packetId = "transaction-\(index)"
            _ = device.addPacket(newPacket: packet)
        }

        #expect(device.packets.count == 1_000)
        #expect(device.packets.first?.packetId == "transaction-1")
        #expect(device.packets.last?.packetId == "transaction-1000")
    }

    @Test("Evicting the selected transaction selects the newest retained transaction")
    @MainActor
    func selectedTransactionEviction() {
        let device = AppTrafficDevice()
        for index in 0...1_000 {
            let packet = AppTrafficPacket()
            packet.packetId = "transaction-\(index)"
            _ = device.addPacket(newPacket: packet)
        }

        #expect(device.selectedPacket?.packetId == "transaction-1000")
    }

    @Test("Device evicts oldest transactions over its payload budget")
    @MainActor
    func transactionPayloadRetention() throws {
        let device = AppTrafficDevice(transactionCountLimit: 10, payloadByteLimit: 5)

        let first = try packet(transactionID: "first", response: Data(repeating: 0x01, count: 4))
        let second = try packet(transactionID: "second", response: Data(repeating: 0x02, count: 4))
        _ = device.addPacket(newPacket: first)
        _ = device.addPacket(newPacket: second)

        #expect(device.packets.map(\.packetId) == ["second"])
        #expect(device.selectedPacket?.packetId == "second")
    }

    @Test("Generated cURL shell-quotes URL, headers, and body")
    func curlShellQuoting() throws {
        let info = try decodeRequestInfo(
            url: "https://example.com/search?q=it's",
            headers: ["X-Name": "O'Brien"],
            body: "customer's data"
        )

        let curl = PacketFormatting.curlString(for: info)

        #expect(curl.contains(#"'https://example.com/search?q=it'\''s'"#))
        #expect(curl.contains(#"-H 'X-Name: O'\''Brien'"#))
        #expect(curl.contains(#"-d 'customer'\''s data'"#))
    }

    @Test("MCP search and cURL exports redact sensitive values")
    @MainActor
    func mcpExportsAreRedacted() async throws {
        let controller = AppTrafficController.shared
        controller.projects.removeAll()
        controller.selectedProject = nil
        TrafficRedactor.setMode(.strict)

        let packetData = try JSONSerialization.data(withJSONObject: [
            "packetId": "sensitive-transaction",
            "requestInfo": [
                "url": "https://example.com/data?token=topsecret",
                "requestHeaders": ["Authorization": "Bearer topsecret"],
                "requestMethod": "GET"
            ],
            "project": ["projectName": "Privacy"],
            "device": ["deviceId": "device-1", "deviceName": "Mac"]
        ])
        let packet = try JSONDecoder().decode(AppTrafficPacket.self, from: packetData)
        _ = controller.addPacket(newPacket: packet)

        let search = try await SearchPacketsTool().execute(arguments: ["query": "topsecret"])
        let curl = try await GetPacketCurlTool().execute(arguments: ["packetId": "sensitive-transaction"])
        let searchText = search.content.first?["text"] ?? ""
        let curlText = curl.content.first?["text"] ?? ""

        #expect(!searchText.contains("topsecret"))
        #expect(searchText.contains("REDACTED"))
        #expect(!curlText.contains("topsecret"))
        #expect(curlText.contains("REDACTED"))
    }

    @Test("PNG response is classified as image media")
    func pngMediaClassification() {
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let result = pngHeader.base64EncodedString().convertBase64ToPrettyJson()
        let overview = result.bodyDisplayResultToOverviewString()

        #expect(overview.localizedCaseInsensitiveContains("image/png"))
    }

    @Test("JPEG signature is classified as image media")
    func jpegMediaClassification() {
        let result = Data([0xFF, 0xD8, 0xFF, 0xE0]).base64EncodedString().convertBase64ToPrettyJson()

        guard case .media(let payload) = result else {
            Issue.record("Expected JPEG data to be classified as media")
            return
        }
        #expect(payload.kind == .image)
        #expect(payload.mimeType == "image/jpeg")
    }

    @Test("Video MIME type is classified as video media")
    func videoMediaClassification() {
        let result = Data([0x00]).base64EncodedString()
            .convertBase64ToPrettyJson(contentType: "video/webm; charset=binary")

        guard case .media(let payload) = result else {
            Issue.record("Expected video MIME type to be classified as media")
            return
        }
        #expect(payload.kind == .video)
        #expect(payload.mimeType == "video/webm")
    }

    @Test("Audio MIME type is classified as audio media")
    func audioMediaClassification() {
        let result = Data([0x00]).base64EncodedString()
            .convertBase64ToPrettyJson(contentType: "audio/mpeg")

        guard case .media(let payload) = result else {
            Issue.record("Expected audio MIME type to be classified as media")
            return
        }
        #expect(payload.kind == .audio)
        #expect(payload.mimeType == "audio/mpeg")
    }

    @Test("Media larger than the preview limit is rejected before decoding")
    func oversizedMediaClassification() {
        let result = Data(repeating: 0x00, count: 6).base64EncodedString()
            .convertBase64ToPrettyJson(contentType: "video/mp4", maxMediaBytes: 3)

        guard case .oversized(let encodedByteCount) = result else {
            Issue.record("Expected oversized media result")
            return
        }
        #expect(encodedByteCount == 8)
    }

    private func decodeRequestInfo(
        url: String,
        headers: [String: String],
        body: String
    ) throws -> AppTrafficRequestInfo {
        let object: [String: Any] = [
            "url": url,
            "requestHeaders": headers,
            "requestBody": Data(body.utf8).base64EncodedString(),
            "requestMethod": "POST"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(AppTrafficRequestInfo.self, from: data)
    }

    private func packet(transactionID: String, response: Data) throws -> AppTrafficPacket {
        let data = try JSONSerialization.data(withJSONObject: [
            "packetId": transactionID,
            "requestInfo": ["responseData": response.base64EncodedString()]
        ])
        return try JSONDecoder().decode(AppTrafficPacket.self, from: data)
    }
}
