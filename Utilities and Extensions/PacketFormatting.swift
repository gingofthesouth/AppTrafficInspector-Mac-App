//
//  PacketFormatting.swift
//  App Traffic Inspector
//
//  Shared formatting for packet detail: cURL, body string, byte size. Used by UI and MCP tools.
//

import Foundation

public enum PacketFormatting {
    /// Max bytes to decode/pretty-print; larger bodies are truncated.
    public static let maxDetailBodyBytes = 512 * 1024

    static func curlString(for info: AppTrafficRequestInfo) -> String {
        curlString(
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
        guard let url else { return "" }
        var base = "curl \(shellQuote(url))"
        if method == .head { base += " --head" }
        var parts = [base]
        if let method, method != .get && method != .head {
            parts.append("-X \(method.rawValue)")
        }
        if let headers {
            for (k, v) in headers where k != "Cookie" {
                parts.append("-H \(shellQuote("\(k): \(v)"))")
            }
        }
        if let b64 = bodyBase64,
           let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
           let str = String(data: data, encoding: .utf8) {
            parts.append("-d \(shellQuote(str))")
        }
        return parts.joined(separator: " \\\n\t")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

    static func byteSizeString(fromBase64 base64: String?) -> String {
        guard let base64 = base64, let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return "0 B" }
        let count = Double(data.count)
        if count < 1024 { return "\(Int(count)) B" }
        if count < 1024 * 1024 { return String(format: "%.1f KB", count / 1024) }
        return String(format: "%.2f MB", count / (1024 * 1024))
    }
}
