//
//  AppTrafficRequestInfo.swift
//  App Traffic Inspector
//

import Cocoa
import SwiftUI

/// HTTP method. Any token is accepted so packets using OPTIONS, CONNECT, TRACE, or custom
/// methods decode instead of being dropped.
struct RequestMethod: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespaces).uppercased()
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let get = RequestMethod(rawValue: "GET")
    static let post = RequestMethod(rawValue: "POST")
    static let put = RequestMethod(rawValue: "PUT")
    static let delete = RequestMethod(rawValue: "DELETE")
    static let patch = RequestMethod(rawValue: "PATCH")
    static let head = RequestMethod(rawValue: "HEAD")
    static let options = RequestMethod(rawValue: "OPTIONS")

    /// Methods that are not safe to repeat without side effects (RFC 9110 §9.2.1).
    var isUnsafe: Bool {
        ![Self.get, .head, .options, RequestMethod(rawValue: "TRACE")].contains(self)
    }

    func color() -> Color {
        switch self {
        case .get: return Color(nsColor: .systemTeal)
        case .put: return Color(nsColor: .systemBlue)
        case .post: return Color(nsColor: .systemOrange)
        case .delete: return Color(nsColor: .systemRed)
        case .patch: return Color(nsColor: .systemPurple)
        default: return .secondary
        }
    }
}

struct AppTrafficRequestInfo: Codable {

    var url: String?
    var requestHeaders: [String: String]?
    var requestBody: String?
    var requestMethod: RequestMethod?

    var responseHeaders: [String: String]?
    var responseData: String?

    /// Accepts number (AppTrafficInspectorKit) or string (legacy Bagel) per wire contract.
    var statusCode: String?

    var startDate: Date?
    var endDate: Date?

    /// Optional producer truncation flags (AppTrafficInspectorKit). Absent means not truncated.
    var requestBodyTruncated: Bool?
    var requestBodyOriginalByteCount: Int?
    var responseDataTruncated: Bool?
    var responseDataOriginalByteCount: Int?

    enum CodingKeys: String, CodingKey {
        case url, requestHeaders, requestBody, requestMethod
        case responseHeaders, responseData, statusCode
        case startDate, endDate
        case requestBodyTruncated, requestBodyOriginalByteCount
        case responseDataTruncated, responseDataOriginalByteCount
    }

    init(
        url: String? = nil,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        requestMethod: RequestMethod? = nil,
        responseHeaders: [String: String]? = nil,
        responseData: String? = nil,
        statusCode: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestMethod = requestMethod
        self.responseHeaders = responseHeaders
        self.responseData = responseData
        self.statusCode = statusCode
        self.startDate = startDate
        self.endDate = endDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        requestHeaders = try c.decodeIfPresent([String: String].self, forKey: .requestHeaders)
        requestBody = try c.decodeIfPresent(String.self, forKey: .requestBody)
        requestMethod = try c.decodeIfPresent(RequestMethod.self, forKey: .requestMethod)
        responseHeaders = try c.decodeIfPresent([String: String].self, forKey: .responseHeaders)
        responseData = try c.decodeIfPresent(String.self, forKey: .responseData)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .statusCode) {
            statusCode = String(n)
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .statusCode) {
            statusCode = s
        } else {
            statusCode = nil
        }
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
        requestBodyTruncated = try? c.decodeIfPresent(Bool.self, forKey: .requestBodyTruncated)
        requestBodyOriginalByteCount = try? c.decodeIfPresent(Int.self, forKey: .requestBodyOriginalByteCount)
        responseDataTruncated = try? c.decodeIfPresent(Bool.self, forKey: .responseDataTruncated)
        responseDataOriginalByteCount = try? c.decodeIfPresent(Int.self, forKey: .responseDataOriginalByteCount)
    }

    var isComplete: Bool { endDate != nil }

    /// Combines a later wire update for the same transaction with this one. Producers send a
    /// transaction several times (start, response, finish) and frames can arrive out of order, so a
    /// stale in-progress update must never erase a status code, headers, or body already received.
    func merged(with newer: AppTrafficRequestInfo) -> AppTrafficRequestInfo {
        if isComplete && !newer.isComplete { return self }
        var result = newer
        result.url = newer.url ?? url
        result.requestHeaders = newer.requestHeaders ?? requestHeaders
        result.requestBody = newer.requestBody ?? requestBody
        result.requestMethod = newer.requestMethod ?? requestMethod
        result.responseHeaders = newer.responseHeaders ?? responseHeaders
        result.responseData = newer.responseData ?? responseData
        result.statusCode = newer.statusCode ?? statusCode
        result.startDate = newer.startDate ?? startDate
        result.endDate = newer.endDate ?? endDate
        result.requestBodyTruncated = newer.requestBodyTruncated ?? requestBodyTruncated
        result.requestBodyOriginalByteCount = newer.requestBodyOriginalByteCount ?? requestBodyOriginalByteCount
        result.responseDataTruncated = newer.responseDataTruncated ?? responseDataTruncated
        result.responseDataOriginalByteCount = newer.responseDataOriginalByteCount ?? responseDataOriginalByteCount
        return result
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(requestHeaders, forKey: .requestHeaders)
        try c.encodeIfPresent(requestBody, forKey: .requestBody)
        try c.encodeIfPresent(requestMethod, forKey: .requestMethod)
        try c.encodeIfPresent(responseHeaders, forKey: .responseHeaders)
        try c.encodeIfPresent(responseData, forKey: .responseData)
        try c.encodeIfPresent(statusCode, forKey: .statusCode)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(endDate, forKey: .endDate)
        try c.encodeIfPresent(requestBodyTruncated, forKey: .requestBodyTruncated)
        try c.encodeIfPresent(requestBodyOriginalByteCount, forKey: .requestBodyOriginalByteCount)
        try c.encodeIfPresent(responseDataTruncated, forKey: .responseDataTruncated)
        try c.encodeIfPresent(responseDataOriginalByteCount, forKey: .responseDataOriginalByteCount)
    }
}
