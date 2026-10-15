//
//  BodyParsing.swift
//  App Traffic Inspector
//
//  Pure, Sendable helpers that turn captured body bytes into inspectable structure:
//  multipart parts, URL-encoded form fields, media signatures, and base64 media embedded in JSON.
//

import Foundation

enum HTTPHeaders {
    static func value(_ name: String, in headers: [String: String]?) -> String? {
        headers?.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Lower-cased MIME type without parameters, e.g. `multipart/form-data`.
    static func mimeType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        let mime = contentType.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mime?.isEmpty == false ? mime : nil
    }

    /// Parses `key=value` / `key="quoted; value"` parameters after the first `;`.
    static func parameters(_ headerValue: String) -> [String: String] {
        var result: [String: String] = [:]
        for segment in splitOutsideQuotes(headerValue, separator: ";").dropFirst() {
            guard let eq = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = segment[segment.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            if key.hasSuffix("*"), let decoded = decodeExtendedValue(value) {
                result[String(key.dropLast())] = decoded
            } else if result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    private static func splitOutsideQuotes(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for char in value {
            if escaped {
                current.append(char)
                escaped = false
            } else if char == "\\" && inQuotes {
                current.append(char)
                escaped = true
            } else if char == "\"" {
                inQuotes.toggle()
                current.append(char)
            } else if char == separator && !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        parts.append(current)
        return parts
    }

    /// RFC 8187 `UTF-8''percent-encoded` values, e.g. `filename*=UTF-8''photo%20one.jpg`.
    private static func decodeExtendedValue(_ value: String) -> String? {
        let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        return String(pieces[2]).removingPercentEncoding
    }
}

// MARK: - Multipart

struct MultipartPart: Identifiable, Hashable, Sendable {
    let index: Int
    let headers: [String: String]
    let name: String?
    let filename: String?
    let contentType: String?
    let body: Data

    var id: Int { index }

    /// Text value for simple form fields; `nil` for file parts and non-UTF-8 payloads.
    var textValue: String? {
        guard filename == nil else { return nil }
        if let mime = HTTPHeaders.mimeType(contentType),
           !(mime.hasPrefix("text/") || mime.contains("json") || mime.contains("xml")
             || mime == "application/x-www-form-urlencoded") {
            return nil
        }
        return String(data: body, encoding: .utf8)
    }
}

enum MultipartParser {
    static func boundary(fromContentType contentType: String?) -> String? {
        guard let contentType,
              HTTPHeaders.mimeType(contentType)?.hasPrefix("multipart/") == true,
              let boundary = HTTPHeaders.parameters(contentType)["boundary"],
              !boundary.isEmpty
        else { return nil }
        return boundary
    }

    /// Splits a multipart body on raw bytes so binary parts are preserved exactly.
    /// Tolerates LF-only line endings and a missing closing delimiter.
    static func parse(_ data: Data, boundary: String) -> [MultipartPart]? {
        let delimiter = Data(("--" + boundary).utf8)
        let delimiterStarts = occurrences(of: delimiter, in: data).filter { start in
            start == data.startIndex || data[start - 1] == 0x0A
        }
        guard !delimiterStarts.isEmpty else { return nil }

        var parts: [MultipartPart] = []
        for (position, start) in delimiterStarts.enumerated() {
            var cursor = start + delimiter.count
            if data[cursor..<min(cursor + 2, data.endIndex)] == Data("--".utf8) { break }
            while cursor < data.endIndex, data[cursor] == 0x20 || data[cursor] == 0x09 { cursor += 1 }
            if cursor < data.endIndex, data[cursor] == 0x0D { cursor += 1 }
            if cursor < data.endIndex, data[cursor] == 0x0A { cursor += 1 }

            var end = position + 1 < delimiterStarts.count ? delimiterStarts[position + 1] : data.endIndex
            if end > cursor, data[end - 1] == 0x0A { end -= 1 }
            if end > cursor, data[end - 1] == 0x0D { end -= 1 }
            guard end >= cursor else { continue }

            if let part = makePart(index: parts.count, raw: data.subdata(in: cursor..<end)) {
                parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts
    }

    private static func makePart(index: Int, raw: Data) -> MultipartPart? {
        let headerEnd: Range<Int>?
        let crlf = raw.range(of: Data("\r\n\r\n".utf8))
        let lf = raw.range(of: Data("\n\n".utf8))
        switch (crlf, lf) {
        case let (c?, l?): headerEnd = c.lowerBound <= l.lowerBound ? c : l
        case let (c?, nil): headerEnd = c
        case let (nil, l?): headerEnd = l
        default: headerEnd = nil
        }

        var headers: [String: String] = [:]
        let body: Data
        if let headerEnd {
            let headerText = String(decoding: raw[raw.startIndex..<headerEnd.lowerBound], as: UTF8.self)
            for line in headerText.split(whereSeparator: \.isNewline) {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
            body = raw.subdata(in: headerEnd.upperBound..<raw.endIndex)
        } else {
            body = raw
        }

        let disposition = HTTPHeaders.value("Content-Disposition", in: headers).map(HTTPHeaders.parameters) ?? [:]
        return MultipartPart(
            index: index,
            headers: headers,
            name: disposition["name"],
            filename: disposition["filename"],
            contentType: HTTPHeaders.value("Content-Type", in: headers),
            body: body
        )
    }

    private static func occurrences(of needle: Data, in haystack: Data) -> [Int] {
        var result: [Int] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, in: searchStart..<haystack.endIndex) {
            result.append(range.lowerBound)
            searchStart = range.upperBound
        }
        return result
    }
}

// MARK: - URL-encoded forms

struct FormField: Hashable, Sendable {
    let name: String
    let value: String
}

enum FormURLEncodedParser {
    static func parse(_ data: Data) -> [FormField]? {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        let fields = text.split(separator: "&", omittingEmptySubsequences: true).map { pair -> FormField in
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            func decode(_ s: Substring?) -> String {
                guard let s else { return "" }
                let spaced = s.replacingOccurrences(of: "+", with: " ")
                return spaced.removingPercentEncoding ?? spaced
            }
            return FormField(name: decode(pieces.first), value: decode(pieces.count > 1 ? pieces[1] : nil))
        }
        return fields.isEmpty ? nil : fields
    }
}

// MARK: - Media sniffing

extension MediaPayload {
    static func classify(data: Data, contentType: String?, filename: String? = nil) -> MediaPayload? {
        if let mime = HTTPHeaders.mimeType(contentType) {
            if mime.hasPrefix("image/") {
                return MediaPayload(data: data, mimeType: mime, kind: .image, filename: filename)
            }
            if mime.hasPrefix("video/") {
                return MediaPayload(data: data, mimeType: mime, kind: .video, filename: filename)
            }
            if mime.hasPrefix("audio/") {
                return MediaPayload(data: data, mimeType: mime, kind: .audio, filename: filename)
            }
            if mime == "application/pdf" {
                return MediaPayload(data: data, mimeType: mime, kind: .document, filename: filename)
            }
        }
        guard let (mime, kind) = sniff(data) else { return nil }
        return MediaPayload(data: data, mimeType: mime, kind: kind, filename: filename)
    }

    /// Identifies common media formats from their leading bytes.
    static func sniff(_ data: Data) -> (mimeType: String, kind: MediaKind)? {
        let bytes = [UInt8](data.prefix(16))
        func ascii(_ range: Range<Int>) -> String? {
            guard bytes.count >= range.upperBound else { return nil }
            return String(bytes: bytes[range], encoding: .ascii)
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return ("image/png", .image) }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return ("image/jpeg", .image) }
        if bytes.starts(with: Array("GIF8".utf8)) { return ("image/gif", .image) }
        if ascii(0..<4) == "RIFF", ascii(8..<12) == "WEBP" { return ("image/webp", .image) }
        if ascii(0..<4) == "RIFF", ascii(8..<12) == "WAVE" { return ("audio/wav", .audio) }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return ("image/tiff", .image)
        }
        if bytes.starts(with: Array("%PDF".utf8)) { return ("application/pdf", .document) }
        if bytes.starts(with: Array("ID3".utf8)) { return ("audio/mpeg", .audio) }
        if ascii(4..<8) == "ftyp", let brand = ascii(8..<12) {
            switch brand {
            case "heic", "heix", "heim", "heis", "hevc", "hevx", "mif1", "msf1":
                return ("image/heic", .image)
            case "avif", "avis":
                return ("image/avif", .image)
            case "qt  ":
                return ("video/quicktime", .video)
            case "M4A ":
                return ("audio/mp4", .audio)
            default:
                return ("video/mp4", .video)
            }
        }
        return nil
    }
}

// MARK: - Base64 media embedded in JSON

struct EmbeddedMedia: Identifiable, Hashable, Sendable {
    /// JSON key path such as `$.user.avatar` or `$.images[2]`.
    let path: String
    let payload: MediaPayload
    var id: String { path }
}

enum EmbeddedMediaFinder {
    /// Strings shorter than this are not worth decoding as possible media.
    static let minimumEncodedLength = 64
    static let maximumResults = 20

    static func find(in jsonObject: Any) -> [EmbeddedMedia] {
        var results: [EmbeddedMedia] = []
        walk(jsonObject, path: "$", into: &results)
        return results
    }

    static func media(fromString string: String) -> MediaPayload? {
        if string.hasPrefix("data:"), let comma = string.firstIndex(of: ",") {
            let header = string[string.index(string.startIndex, offsetBy: 5)..<comma]
            guard header.lowercased().hasSuffix(";base64") else { return nil }
            let declared = header.split(separator: ";").first.map(String.init)
            guard let data = Data(base64Encoded: String(string[string.index(after: comma)...]),
                                  options: .ignoreUnknownCharacters)
            else { return nil }
            return MediaPayload.classify(data: data, contentType: declared)
        }
        guard string.utf8.count >= minimumEncodedLength,
              string.utf8.allSatisfy(isBase64Byte),
              let data = Data(base64Encoded: string, options: .ignoreUnknownCharacters)
        else { return nil }
        return MediaPayload.classify(data: data, contentType: nil)
    }

    private static func walk(_ value: Any, path: String, into results: inout [EmbeddedMedia]) {
        guard results.count < maximumResults else { return }
        switch value {
        case let dict as [String: Any]:
            for key in dict.keys.sorted() {
                walk(dict[key] as Any, path: "\(path).\(key)", into: &results)
            }
        case let array as [Any]:
            for (index, element) in array.enumerated() {
                walk(element, path: "\(path)[\(index)]", into: &results)
            }
        case let string as String:
            if let payload = media(fromString: string) {
                results.append(EmbeddedMedia(path: path, payload: payload))
            }
        default:
            break
        }
    }

    private static func isBase64Byte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="),
             UInt8(ascii: "-"), UInt8(ascii: "_"), 0x0A, 0x0D:
            return true
        default:
            return false
        }
    }
}

// MARK: - Binary helpers

enum BinaryFormatting {
    /// Classic 16-bytes-per-row hex dump with an ASCII gutter.
    static func hexDump(_ data: Data, limit: Int = 512) -> String {
        let bytes = [UInt8](data.prefix(limit))
        var lines: [String] = []
        for rowStart in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[rowStart..<min(rowStart + 16, bytes.count)]
            let hex = row.map { String(format: "%02x", $0) }.joined(separator: " ")
            let padded = hex.padding(toLength: 47, withPad: " ", startingAt: 0)
            let text = String(row.map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : "." })
            lines.append(String(format: "%08x  ", rowStart) + padded + "  |" + text + "|")
        }
        if data.count > limit {
            lines.append("… \(data.count - limit) more bytes")
        }
        return lines.joined(separator: "\n")
    }

    static func fileExtension(forMimeType mimeType: String?) -> String? {
        guard let mime = HTTPHeaders.mimeType(mimeType) else { return nil }
        let known: [String: String] = [
            "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
            "image/heic": "heic", "image/avif": "avif", "image/tiff": "tiff", "image/bmp": "bmp",
            "video/mp4": "mp4", "video/quicktime": "mov", "audio/mpeg": "mp3", "audio/mp4": "m4a",
            "audio/wav": "wav", "application/pdf": "pdf", "application/json": "json",
            "text/plain": "txt", "application/octet-stream": "bin"
        ]
        return known[mime]
    }

    /// Makes a filename safe to place in a directory and inside a cURL `-F` argument.
    static func sanitizedFilename(_ name: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:\"';,\n\r\t").union(.controlCharacters)
        let cleaned = name.unicodeScalars.map { disallowed.contains($0) ? "_" : String($0) }.joined()
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "file" : String(trimmed.prefix(120))
    }
}
