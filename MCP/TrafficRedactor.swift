//
//  TrafficRedactor.swift
//  App Traffic Inspector
//
//  Privacy redaction for MCP tool responses. Headers, URL params, body patterns, JSON field names.
//

import Foundation

public enum RedactionMode: String, CaseIterable, Sendable {
    case strict
    case moderate
    case off
}

public enum TrafficRedactor {
    private static let sensitiveHeaderNames: Set<String> = [
        "Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
        "X-API-Key", "X-Auth-Token", "X-CSRF-Token", "WWW-Authenticate"
    ]
    private static let sensitiveQueryParamNames: Set<String> = [
        "api_key", "apikey", "token", "access_token", "secret", "password", "key"
    ]
    private static let sensitiveJSONKeys: Set<String> = [
        "password", "passwd", "secret", "token", "access_token", "refresh_token",
        "api_key", "apiKey", "private_key", "privateKey", "ssn", "credit_card",
        "card_number", "cvv", "pin", "authorization"
    ]
    private static let redactedPlaceholder = "[REDACTED]"
    private static let redactedPlaceholderWithReason = "[REDACTED — MCP privacy mode]"

    // MARK: - UserDefaults keys
    public static let redactionModeKey = "mcpRedactionMode"
    public static let customRedactionFieldsKey = "mcpCustomRedactionFields"

    public static func currentMode() -> RedactionMode {
        let raw = UserDefaults.standard.string(forKey: redactionModeKey) ?? RedactionMode.strict.rawValue
        return RedactionMode(rawValue: raw) ?? .strict
    }

    public static func setMode(_ mode: RedactionMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: redactionModeKey)
    }

    public static func customRedactionFieldNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: customRedactionFieldsKey) ?? []
    }

    public static func setCustomRedactionFieldNames(_ names: [String]) {
        UserDefaults.standard.set(names, forKey: customRedactionFieldsKey)
    }

    // MARK: - Header redaction
    public static func redact(headers: [String: String]?, mode: RedactionMode) -> [String: String] {
        guard mode != .off, let headers = headers, !headers.isEmpty else { return headers ?? [:] }
        var out: [String: String] = [:]
        let custom = Set(customRedactionFieldNames().map { $0.lowercased() })
        for (key, value) in headers {
            if sensitiveHeaderNames.contains(key) || custom.contains(key.lowercased()) {
                out[key] = redactedPlaceholderWithReason
            } else {
                out[key] = value
            }
        }
        return out
    }

    // MARK: - URL redaction (query params)
    public static func redactURL(urlString: String?, mode: RedactionMode) -> String? {
        guard mode == .strict, let urlString = urlString, let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty
        else { return urlString }
        let custom = Set(customRedactionFieldNames().map { $0.lowercased() })
        let redacted = items.map { item -> URLQueryItem in
            let nameLower = item.name.lowercased()
            if sensitiveQueryParamNames.contains(nameLower) || custom.contains(nameLower) {
                return URLQueryItem(name: item.name, value: redactedPlaceholder)
            }
            return item
        }
        components.queryItems = redacted
        return components.url?.absoluteString ?? urlString
    }

    // MARK: - Body pattern redaction (regex)
    public static func redactBody(text: String?, mode: RedactionMode) -> String? {
        guard mode == .strict, var text = text, !text.isEmpty else { return text }

        // Bearer tokens
        if let re = try? NSRegularExpression(pattern: #"Bearer\s+[^\s]+"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "Bearer \(redactedPlaceholder)")
        }
        // JWT (three base64 segments separated by dots)
        if let re = try? NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: redactedPlaceholder)
        }
        // Email (simple)
        if let re = try? NSRegularExpression(pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[EMAIL_REDACTED]")
        }
        // Credit card (4-4-4-4 or 4 groups of 4)
        if let re = try? NSRegularExpression(pattern: #"\b(?:\d{4}[- ]?){3}\d{4}\b"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[CC_REDACTED]")
        }
        return text
    }

    // MARK: - JSON field-name redaction (walk structure)
    public static func redactJSONFields(data: Data?, mode: RedactionMode) -> Data? {
        guard mode == .strict, let data = data else { return data }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return data }
        var custom = Set(customRedactionFieldNames().map { $0.lowercased() })
        for k in sensitiveJSONKeys { custom.insert(k.lowercased()) }
        guard let redacted = redactJSONValue(json, sensitiveKeys: custom) else { return data }
        return try? JSONSerialization.data(withJSONObject: redacted)
    }

    private static func redactJSONValue(_ value: Any, sensitiveKeys: Set<String>) -> Any? {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if sensitiveKeys.contains(k.lowercased()) {
                    out[k] = redactedPlaceholder
                } else if let r = redactJSONValue(v, sensitiveKeys: sensitiveKeys) {
                    out[k] = r
                } else {
                    out[k] = v
                }
            }
            return out
        }
        if let arr = value as? [Any] {
            return arr.compactMap { redactJSONValue($0, sensitiveKeys: sensitiveKeys) }
        }
        return value
    }

    /// Full redaction of request info for MCP: headers, URL, request body, response body.
    public static func redactRequestInfo(
        url: String?,
        requestHeaders: [String: String]?,
        requestBody: String?,
        responseHeaders: [String: String]?,
        responseData: String?,
        mode: RedactionMode
    ) -> (url: String?, requestHeaders: [String: String], responseHeaders: [String: String], requestBody: String?, responseData: String?, headersRedacted: Int, bodyFieldsRedacted: Int) {
        let rHeaders = redact(headers: requestHeaders, mode: mode)
        let rRespHeaders = redact(headers: responseHeaders, mode: mode)
        let headersRedacted = (requestHeaders?.filter { sensitiveHeaderNames.contains($0.key) }.count ?? 0) + (responseHeaders?.filter { sensitiveHeaderNames.contains($0.key) }.count ?? 0)

        let rUrl = redactURL(urlString: url, mode: mode)

        var rReqBody = requestBody
        var rRespBody = responseData
        var bodyFieldsRedacted = 0
        if mode == .strict {
            rReqBody = redactBase64Body(requestBody)
            rRespBody = redactBase64Body(responseData)
            bodyFieldsRedacted += rReqBody != requestBody ? 1 : 0
            bodyFieldsRedacted += rRespBody != responseData ? 1 : 0
        }
        return (rUrl, rHeaders, rRespHeaders, rReqBody, rRespBody, headersRedacted, bodyFieldsRedacted)
    }

    private static func redactBase64Body(_ encoded: String?) -> String? {
        guard let encoded,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let source = String(data: data, encoding: .utf8)
        else {
            return encoded
        }
        let jsonRedacted = redactJSONFields(data: data, mode: .strict) ?? data
        let jsonText = String(data: jsonRedacted, encoding: .utf8) ?? source
        let patternRedacted = redactBody(text: jsonText, mode: .strict) ?? jsonText
        return Data(patternRedacted.utf8).base64EncodedString()
    }
}
