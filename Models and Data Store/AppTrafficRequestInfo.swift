//
//  AppTrafficRequestInfo.swift
//  App Traffic Inspector
//

import Cocoa
import SwiftUI

enum RequestMethod: String, Codable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    
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

    enum CodingKeys: String, CodingKey {
        case url, requestHeaders, requestBody, requestMethod
        case responseHeaders, responseData, statusCode
        case startDate, endDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        requestHeaders = try c.decodeIfPresent([String: String].self, forKey: .requestHeaders)
        requestBody = try c.decodeIfPresent(String.self, forKey: .requestBody)
        requestMethod = try c.decodeIfPresent(RequestMethod.self, forKey: .requestMethod)
        responseHeaders = try c.decodeIfPresent([String: String].self, forKey: .responseHeaders)
        responseData = try c.decodeIfPresent(String.self, forKey: .responseData)
        if let n = try c.decodeIfPresent(Int.self, forKey: .statusCode) {
            statusCode = String(n)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .statusCode) {
            statusCode = s
        } else {
            statusCode = nil
        }
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
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
    }
}
