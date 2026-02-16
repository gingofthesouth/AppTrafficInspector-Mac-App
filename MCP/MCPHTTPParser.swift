//
//  MCPHTTPParser.swift
//  App Traffic Inspector
//
//  Minimal HTTP/1.1 request parser and response builder for MCP Streamable HTTP.
//

import Foundation

struct MCPHTTPRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data?
}

struct MCPHTTPParser {
    enum ParseError: Error, Sendable {
        case incomplete
        case invalidRequestLine
        case invalidHeader
    }

    /// Parse bytes into request line, headers, and body (by Content-Length).
    static func parseRequest(_ data: inout Data) throws -> MCPHTTPRequest? {
        guard let firstLineEnd = data.firstRange(of: Data("\r\n".utf8)) else { return nil }
        let requestLine = data.prefix(upTo: firstLineEnd.startIndex)
        data.removeSubrange(..<firstLineEnd.endIndex)
        guard let lineStr = String(data: requestLine, encoding: .utf8) else { throw ParseError.invalidRequestLine }
        let parts = lineStr.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw ParseError.invalidRequestLine }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        while true {
            guard let lineEnd = data.firstRange(of: Data("\r\n".utf8)) else { return nil }
            let lineData = data.prefix(upTo: lineEnd.startIndex)
            data.removeSubrange(..<lineEnd.endIndex)
            if lineData.isEmpty { break }
            guard let line = String(data: lineData, encoding: .utf8) else { throw ParseError.invalidHeader }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if contentLength > 0 {
            guard data.count >= contentLength else { throw ParseError.incomplete }
            let body = Data(data.prefix(contentLength))
            data.removeSubrange(data.startIndex..<data.index(data.startIndex, offsetBy: contentLength))
            return MCPHTTPRequest(method: method, path: path, headers: headers, body: body)
        }
        return MCPHTTPRequest(method: method, path: path, headers: headers, body: nil)
    }

    /// Build HTTP response bytes.
    static func response(statusCode: Int, headers: [String: String], body: Data?) -> Data {
        let statusText = statusTextFor(code: statusCode)
        var lines: [String] = ["HTTP/1.1 \(statusCode) \(statusText)"]
        var h = headers
        if let body = body {
            h["Content-Length"] = String(body.count)
        }
        for (k, v) in h.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            lines.append("\(k): \(v)")
        }
        lines.append("")
        lines.append("")
        var data = lines.joined(separator: "\r\n").data(using: .utf8)!
        if let body = body { data.append(body) }
        return data
    }

    static func response(statusCode: Int, body: Data?) -> Data {
        var headers: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
        if body == nil { headers["Content-Length"] = "0" }
        return response(statusCode: statusCode, headers: headers, body: body)
    }

    static func response(statusCode: Int, jsonBody: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: jsonBody)) ?? Data()
        return response(statusCode: statusCode, body: body)
    }

    /// SSE response headers (no Content-Length; stream stays open).
    static func sseHeaders(extraHeaders: [String: String] = [:]) -> Data {
        var headers: [String: String] = [
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive"
        ]
        for (k, v) in extraHeaders { headers[k] = v }
        return response(statusCode: 200, headers: headers, body: nil)
    }

    /// One SSE frame: "data: {json}\n\n"
    static func sseFrame(jsonBody: [String: Any]) -> Data {
        let json = (try? JSONSerialization.data(withJSONObject: jsonBody)) ?? Data()
        let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
        let line = "data: \(jsonStr)\n\n"
        return Data(line.utf8)
    }

    private static func statusTextFor(code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Unknown"
        }
    }
}
