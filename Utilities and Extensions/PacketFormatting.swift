//
//  PacketFormatting.swift
//  App Traffic Inspector
//
//  Shared formatting for packet detail: cURL, body string, byte size. Used by UI and MCP tools.
//

import Foundation

enum CurlBody: Equatable {
    case none
    case text(String)
    case file(URL)
    case multipart([CurlFormField])
    case omitted(String)
}

struct CurlFormField: Equatable {
    enum Value: Equatable {
        case text(String)
        case file(URL, filename: String?, contentType: String?)
    }

    let name: String
    let value: Value
}

enum PacketFormatting {
    /// Max bytes to decode/pretty-print; larger bodies are truncated.
    static let maxDetailBodyBytes = 512 * 1024

    // MARK: - cURL

    /// Text-only cURL for contexts without file access (MCP). Binary bodies are noted, not exported.
    static func curlString(for info: AppTrafficRequestInfo) -> String {
        truncationWarning(for: info) + curlString(
            url: info.url,
            method: info.requestMethod,
            headers: info.requestHeaders,
            bodyBase64: info.requestBody
        )
    }

    static func curlString(
        url: String?,
        method: RequestMethod?,
        headers: [String: String]?,
        bodyBase64: String?
    ) -> String {
        let body: CurlBody
        if let bodyBase64, let data = Data(base64Encoded: bodyBase64, options: .ignoreUnknownCharacters), !data.isEmpty {
            if let text = String(data: data, encoding: .utf8) {
                body = .text(text)
            } else {
                body = .omitted("binary request body (\(data.count) bytes) omitted; copy cURL from the app to export it")
            }
        } else {
            body = .none
        }
        return curlString(url: url, method: method, headers: headers, body: body)
    }

    /// Full-fidelity cURL. Non-text bodies are written via `writeFile(data, filename)` and referenced with `@path`.
    static func curlString(
        for info: AppTrafficRequestInfo,
        writeFile: (Data, String) throws -> URL
    ) -> String {
        truncationWarning(for: info) + curlString(
            url: info.url,
            method: info.requestMethod,
            headers: info.requestHeaders,
            body: curlBody(for: info, writeFile: writeFile)
        )
    }

    /// Comment line warning that the captured request body is incomplete, or empty.
    static func truncationWarning(for info: AppTrafficRequestInfo) -> String {
        guard info.requestBodyTruncated == true else { return "" }
        let captured = Data(base64Encoded: info.requestBody ?? "", options: .ignoreUnknownCharacters)?.count ?? 0
        let original = info.requestBodyOriginalByteCount.map { " of \($0)" } ?? ""
        return "# Warning: request body was truncated by AppTrafficInspectorKit (\(captured)\(original) bytes captured); this command sends an incomplete body.\n"
    }

    static func curlBody(
        for info: AppTrafficRequestInfo,
        writeFile: (Data, String) throws -> URL
    ) -> CurlBody {
        guard let b64 = info.requestBody,
              let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              !data.isEmpty
        else { return .none }

        let contentType = HTTPHeaders.value("Content-Type", in: info.requestHeaders)
        do {
            if HTTPHeaders.mimeType(contentType) == "multipart/form-data",
               let boundary = MultipartParser.boundary(fromContentType: contentType),
               let parts = MultipartParser.parse(data, boundary: boundary) {
                let fields = try parts.map { part -> CurlFormField in
                    let name = part.name ?? "part\(part.index)"
                    if let text = part.textValue {
                        return CurlFormField(name: name, value: .text(text))
                    }
                    let base = part.filename.map(BinaryFormatting.sanitizedFilename) ?? BinaryFormatting.sanitizedFilename(name)
                    let ext = part.filename == nil ? (BinaryFormatting.fileExtension(forMimeType: part.contentType)).map { "." + $0 } ?? "" : ""
                    let url = try writeFile(part.body, "part-\(part.index)-\(base)\(ext)")
                    return CurlFormField(name: name, value: .file(url, filename: part.filename, contentType: part.contentType))
                }
                return .multipart(fields)
            }
            if let text = String(data: data, encoding: .utf8) {
                return .text(text)
            }
            let ext = BinaryFormatting.fileExtension(forMimeType: contentType)
                ?? MediaPayload.sniff(data).flatMap { BinaryFormatting.fileExtension(forMimeType: $0.mimeType) }
                ?? "bin"
            return .file(try writeFile(data, "request-body.\(ext)"))
        } catch {
            return .omitted("request body (\(data.count) bytes) could not be exported: \(error.localizedDescription)")
        }
    }

    static func curlString(
        url: String?,
        method: RequestMethod?,
        headers: [String: String]?,
        body: CurlBody
    ) -> String {
        guard let url else { return "" }
        var base = "curl \(shellQuote(url))"
        if method == .head { base += " --head" }
        var parts = [base]
        let hasBody: Bool
        switch body {
        case .none, .omitted: hasBody = false
        default: hasBody = true
        }
        if let method, method != .head, method != .get || hasBody {
            parts.append("-X \(method.rawValue)")
        }

        var skipped: Set<String> = ["content-length"]
        if case .multipart = body { skipped.insert("content-type") }
        if let headers {
            for key in headers.keys.sorted() where !skipped.contains(key.lowercased()) {
                parts.append("-H \(shellQuote("\(key): \(headers[key] ?? "")"))")
            }
        }

        var comment = ""
        switch body {
        case .none:
            break
        case .text(let text):
            parts.append("--data-raw \(shellQuote(text))")
        case .file(let fileURL):
            parts.append("--data-binary \(shellQuote("@" + fileURL.path))")
        case .multipart(let fields):
            for field in fields {
                switch field.value {
                case .text(let text):
                    parts.append("--form-string \(shellQuote("\(field.name)=\(text)"))")
                case .file(let fileURL, let filename, let contentType):
                    var spec = "\(field.name)=@\(curlFormQuote(fileURL.path))"
                    if let filename { spec += ";filename=\(curlFormQuote(filename))" }
                    if let contentType { spec += ";type=\(contentType)" }
                    parts.append("-F \(shellQuote(spec))")
                }
            }
        case .omitted(let reason):
            comment = "# Note: \(reason)\n"
        }
        return comment + parts.joined(separator: " \\\n\t")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Quotes a value inside a curl `-F` spec so `;` and `,` in paths or filenames are literal.
    private static func curlFormQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func dataString(fromBase64 base64: String?, pretty: Bool, maxBytes: Int = PacketFormatting.maxDetailBodyBytes) -> String {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return "" }
        let capped = data.count > maxBytes ? Data(data.prefix(maxBytes)) : data
        let truncatedSuffix = data.count > maxBytes ? "\n\n… (truncated, total \(data.count) bytes)" : ""
        if pretty {
            if let obj = try? JSONSerialization.jsonObject(with: capped, options: .mutableContainers),
               let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
               let str = String(data: prettyData, encoding: .utf8) {
                return str.replacingOccurrences(of: "\\/", with: "/") + truncatedSuffix
            }
        }
        if let str = String(data: capped, encoding: .utf8) { return str + truncatedSuffix }
        return "(binary data \(data.count) bytes)"
    }

    /// Clipboard text for a body: multipart becomes a part summary, binary a size note.
    static func bodyText(fromBase64 base64: String?, contentType: String?) -> String {
        if HTTPHeaders.mimeType(contentType) == "multipart/form-data",
           let base64,
           let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
           let boundary = MultipartParser.boundary(fromContentType: contentType),
           let parts = MultipartParser.parse(data, boundary: boundary) {
            return MultipartSummary.text(for: parts)
        }
        return dataString(fromBase64: base64, pretty: true)
    }

    static func byteSizeString(fromBase64 base64: String?) -> String {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return "0 B" }
        let count = Double(data.count)
        if count < 1024 { return "\(Int(count)) B" }
        if count < 1024 * 1024 { return String(format: "%.1f KB", count / 1024) }
        return String(format: "%.2f MB", count / (1024 * 1024))
    }
}
