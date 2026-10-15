//
//  BodyInspectionTests.swift
//  AppTrafficInspectorTests
//

@testable import App_Traffic_Inspector
import Foundation
import Testing

struct BodyInspectionTests {

    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0xFF, 0x00])

    static func multipartBody(boundary: String, lineEnding: String = "\r\n", terminate: Bool = true) -> Data {
        var data = Data()
        func append(_ s: String) { data.append(Data(s.utf8)) }
        append("--\(boundary)\(lineEnding)")
        append("Content-Disposition: form-data; name=\"caption\"\(lineEnding)\(lineEnding)")
        append("Hello; world\(lineEnding)")
        append("--\(boundary)\(lineEnding)")
        append("Content-Disposition: form-data; name=\"avatar\"; filename=\"me.png\"\(lineEnding)")
        append("Content-Type: image/png\(lineEnding)\(lineEnding)")
        data.append(png)
        append(lineEnding)
        if terminate { append("--\(boundary)--\(lineEnding)") }
        return data
    }

    // MARK: Multipart

    @Test("Multipart parses text and binary parts with bytes intact")
    func multipartParsesParts() throws {
        let contentType = #"multipart/form-data; boundary="Abc123""#
        let boundary = try #require(MultipartParser.boundary(fromContentType: contentType))
        #expect(boundary == "Abc123")
        let parts = try #require(MultipartParser.parse(Self.multipartBody(boundary: boundary), boundary: boundary))
        #expect(parts.count == 2)
        #expect(parts[0].name == "caption")
        #expect(parts[0].textValue == "Hello; world")
        #expect(parts[1].name == "avatar")
        #expect(parts[1].filename == "me.png")
        #expect(parts[1].contentType == "image/png")
        #expect(parts[1].body == Self.png)
        #expect(parts[1].textValue == nil)
    }

    @Test("Multipart tolerates LF line endings and a missing terminator")
    func multipartLenient() throws {
        let lf = try #require(MultipartParser.parse(Self.multipartBody(boundary: "b", lineEnding: "\n"), boundary: "b"))
        #expect(lf.count == 2)
        #expect(lf[1].body == Self.png)
        let open = try #require(MultipartParser.parse(Self.multipartBody(boundary: "b", terminate: false), boundary: "b"))
        #expect(open.count == 2)
        #expect(open[1].body == Self.png)
    }

    @Test("RFC 8187 filename* is decoded")
    func extendedFilename() {
        let params = HTTPHeaders.parameters(#"form-data; name="f"; filename*=UTF-8''caf%C3%A9.png"#)
        #expect(params["filename"] == "café.png")
    }

    @Test("Body inspector routes multipart, form, media, JSON and binary")
    func inspectorRouting() {
        if case .multipart(let parts) = BodyInspector.inspect(Self.multipartBody(boundary: "x"), contentType: "multipart/form-data; boundary=x") {
            #expect(parts.count == 2)
        } else { Issue.record("expected multipart") }

        if case .form(let fields) = BodyInspector.inspect(Data("a=1&b=hello+world%21".utf8), contentType: "application/x-www-form-urlencoded") {
            #expect(fields == [FormField(name: "a", value: "1"), FormField(name: "b", value: "hello world!")])
        } else { Issue.record("expected form") }

        if case .media(let payload) = BodyInspector.inspect(Self.png, contentType: "application/octet-stream") {
            #expect(payload.kind == .image)
        } else { Issue.record("expected sniffed media") }

        if case .binary = BodyInspector.inspect(Data([0x00, 0x01, 0xFE, 0xFF, 0x80]), contentType: nil) {
        } else { Issue.record("expected binary") }
    }

    @Test("Sniffing detects HEIC, WebP and PDF")
    func sniffing() {
        let heic = Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8) + Data(repeating: 0, count: 8)
        #expect(MediaPayload.sniff(heic)?.mimeType == "image/heic")
        let webp = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBPVP8 ".utf8)
        #expect(MediaPayload.sniff(webp)?.mimeType == "image/webp")
        let pdf = Data("%PDF-1.7\n".utf8)
        #expect(MediaPayload.sniff(pdf)?.kind == .document)
        #expect(MediaPayload.sniff(Data("BM is not a bitmap".utf8)) == nil)
    }

    @Test("Base64 images inside JSON are found with their path")
    func embeddedMedia() throws {
        let b64 = Self.png.base64EncodedString() + String(repeating: "A", count: 80)
        let json: [String: Any] = [
            "user": ["avatar": "data:image/png;base64,\(Self.png.base64EncodedString())"],
            "photos": [["raw": b64]],
            "name": "short",
        ]
        let found = EmbeddedMediaFinder.find(in: json)
        let paths = Set(found.map(\.path))
        #expect(paths.contains("$.user.avatar"))
        #expect(paths.contains("$.photos[0].raw"))
        #expect(found.allSatisfy { $0.payload.kind == .image })
    }

    // MARK: Model decoding

    @Test("Packets with OPTIONS and custom methods decode instead of being dropped")
    func unknownMethodsDecode() throws {
        for method in ["OPTIONS", "PROPFIND", "purge"] {
            let data = try JSONSerialization.data(withJSONObject: ["url": "https://x", "requestMethod": method])
            let info = try JSONDecoder().decode(AppTrafficRequestInfo.self, from: data)
            #expect(info.requestMethod?.rawValue == method.uppercased())
        }
        #expect(RequestMethod.post.isUnsafe)
        #expect(!RequestMethod.get.isUnsafe)
        #expect(!RequestMethod.options.isUnsafe)
    }

    @Test("Producer truncation flags decode when present and default to nil")
    func truncationFlags() throws {
        let flagged = try JSONSerialization.data(withJSONObject: [
            "requestBodyTruncated": true, "requestBodyOriginalByteCount": 9_000_000,
        ])
        let info = try JSONDecoder().decode(AppTrafficRequestInfo.self, from: flagged)
        #expect(info.requestBodyTruncated == true)
        #expect(info.requestBodyOriginalByteCount == 9_000_000)
        let legacy = try JSONDecoder().decode(AppTrafficRequestInfo.self, from: Data("{}".utf8))
        #expect(legacy.requestBodyTruncated == nil)
        #expect(legacy.responseDataTruncated == nil)
    }

    @Test("Replay fields are not part of the wire format")
    func replayFieldsNotEncoded() throws {
        let packet = AppTrafficPacket()
        packet.packetId = "p"
        packet.replayOfPacketId = "orig"
        let json = String(decoding: try JSONEncoder().encode(packet), as: UTF8.self)
        #expect(!json.contains("replay"))
    }

    // MARK: cURL

    @Test("Text bodies use --data-raw, Cookie is kept, Content-Length dropped")
    func curlText() {
        let curl = PacketFormatting.curlString(
            url: "https://api.example.com/v1",
            method: .post,
            headers: ["Cookie": "session=abc", "Content-Length": "4", "Content-Type": "application/json"],
            body: .text("{}")
        )
        #expect(curl.contains("-X POST"))
        #expect(curl.contains("-H 'Cookie: session=abc'"))
        #expect(!curl.contains("Content-Length"))
        #expect(curl.contains("--data-raw '{}'"))
    }

    @Test("GET without body omits -X; HEAD uses --head")
    func curlMethods() {
        let get = PacketFormatting.curlString(url: "https://x", method: .get, headers: nil, body: .none)
        #expect(!get.contains("-X"))
        let head = PacketFormatting.curlString(url: "https://x", method: .head, headers: nil, body: .none)
        #expect(head.contains("--head"))
        #expect(!head.contains("-X"))
        let options = PacketFormatting.curlString(url: "https://x", method: .options, headers: nil, body: .none)
        #expect(options.contains("-X OPTIONS"))
    }

    @Test("Binary bodies are exported and referenced with --data-binary @file")
    func curlBinaryExport() throws {
        let info = AppTrafficRequestInfo(
            url: "https://upload.example.com",
            requestHeaders: ["Content-Type": "image/png"],
            requestBody: Self.png.base64EncodedString(),
            requestMethod: .put
        )
        var written: [(Data, String)] = []
        let curl = PacketFormatting.curlString(for: info) { data, name in
            written.append((data, name))
            return URL(fileURLWithPath: "/tmp/export/\(name)")
        }
        #expect(written.count == 1)
        #expect(written.first?.0 == Self.png)
        #expect(written.first?.1 == "request-body.png")
        #expect(curl.contains("--data-binary '@/tmp/export/request-body.png'"))
        #expect(curl.contains("-H 'Content-Type: image/png'"))
    }

    @Test("Multipart bodies become -F file parts and --form-string text parts")
    func curlMultipart() throws {
        let info = AppTrafficRequestInfo(
            url: "https://upload.example.com",
            requestHeaders: ["Content-Type": "multipart/form-data; boundary=zz", "Content-Length": "999"],
            requestBody: Self.multipartBody(boundary: "zz").base64EncodedString(),
            requestMethod: .post
        )
        var files: [String] = []
        let curl = PacketFormatting.curlString(for: info) { data, name in
            files.append(name)
            #expect(data == Self.png)
            return URL(fileURLWithPath: "/tmp/x/\(name)")
        }
        #expect(files == ["part-1-me.png"])
        #expect(curl.contains("--form-string 'caption=Hello; world'"))
        #expect(curl.contains(#"-F 'avatar=@"/tmp/x/part-1-me.png";filename="me.png";type=image/png'"#))
        #expect(!curl.contains("Content-Type: multipart"))
        #expect(!curl.contains("Content-Length"))
    }

    @Test("MCP cURL notes omitted binary bodies instead of corrupting them")
    func curlTextOnlyBinaryNote() {
        let curl = PacketFormatting.curlString(
            url: "https://x", method: .post, headers: nil,
            bodyBase64: Data([0xFF, 0xFE, 0x00]).base64EncodedString()
        )
        #expect(curl.hasPrefix("# Note: binary request body (3 bytes) omitted"))
        #expect(!curl.contains("--data"))
    }

    @Test("Export failures are reported in the command, not thrown")
    func curlExportFailure() {
        struct Failure: Error {}
        let info = AppTrafficRequestInfo(url: "https://x", requestBody: Self.png.base64EncodedString(), requestMethod: .post)
        let curl = PacketFormatting.curlString(for: info) { _, _ in throw Failure() }
        #expect(curl.hasPrefix("# Note: request body (18 bytes) could not be exported"))
    }

    // MARK: Replay

    @Test("Replay request strips hop-by-hop headers and sends the raw body")
    func replayRequest() throws {
        let info = AppTrafficRequestInfo(
            url: "https://api.example.com/upload",
            requestHeaders: ["Host": "api.example.com", "Content-Length": "18", "Connection": "keep-alive",
                             "Authorization": "Bearer t", "Cookie": "a=b", "Content-Type": "image/png"],
            requestBody: Self.png.base64EncodedString(),
            requestMethod: .put
        )
        let request = try ReplayRequestBuilder.makeRequest(from: info)
        #expect(request.httpMethod == "PUT")
        #expect(request.httpBody == Self.png)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "a=b")
        #expect(request.value(forHTTPHeaderField: "Host") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Length") == nil)
        #expect(request.value(forHTTPHeaderField: "Connection") == nil)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test("Replay rejects missing and non-HTTP URLs")
    func replayRejectsBadURLs() {
        #expect(throws: ReplayRequestBuilder.BuildError.self) {
            try ReplayRequestBuilder.makeRequest(from: AppTrafficRequestInfo())
        }
        #expect(throws: ReplayRequestBuilder.BuildError.self) {
            try ReplayRequestBuilder.makeRequest(from: AppTrafficRequestInfo(url: "file:///etc/passwd"))
        }
    }

    @Test("Replay comparison diffs response headers case-insensitively")
    func headerDiff() {
        let diffs = ReplayComparison.headerDifferences(
            original: ["Content-Type": "image/png", "ETag": "1", "X-Old": "y"],
            replay: ["content-type": "image/png", "ETag": "2", "X-New": "z"]
        )
        let byName = Dictionary(uniqueKeysWithValues: diffs.map { ($0.name.lowercased(), $0.change) })
        #expect(byName["content-type"] == .same)
        #expect(byName["etag"] == .changed)
        #expect(byName["x-old"] == .removed)
        #expect(byName["x-new"] == .added)
    }

    @Test("Clipboard text summarises multipart parts")
    func multipartClipboard() {
        let text = PacketFormatting.bodyText(
            fromBase64: Self.multipartBody(boundary: "q").base64EncodedString(),
            contentType: "multipart/form-data; boundary=q"
        )
        #expect(text.contains("caption = Hello; world"))
        #expect(text.contains("avatar = [file: filename=me.png, image/png, 18 bytes]"))
    }

    @Test("cURL warns when the Kit truncated the request body")
    func curlTruncationWarning() throws {
        let truncated = try JSONSerialization.data(withJSONObject: [
            "url": "https://example.com/upload", "requestMethod": "POST",
            "requestBody": Data("abc".utf8).base64EncodedString(),
            "requestBodyTruncated": true, "requestBodyOriginalByteCount": 10,
        ])
        let info = try JSONDecoder().decode(AppTrafficRequestInfo.self, from: truncated)
        let curl = PacketFormatting.curlString(for: info)
        #expect(curl.hasPrefix("# Warning: request body was truncated by AppTrafficInspectorKit (3 of 10 bytes captured)"))
        #expect(curl.contains("--data-raw 'abc'"))

        let complete = try JSONDecoder().decode(AppTrafficRequestInfo.self, from: JSONSerialization.data(withJSONObject: [
            "url": "https://example.com/upload", "requestMethod": "POST",
        ]))
        #expect(!PacketFormatting.curlString(for: complete).contains("# Warning"))
    }
}
