//
//  OverviewContentAsync.swift
//  AppTrafficInspector
//
//  Created by Ernest Cunningham on 16/02/2026.
//  Copyright © 2026 Yagiz Lab. All rights reserved.
//


import SwiftUI
import AppKit

struct OverviewContentAsync: View {
    let info: AppTrafficRequestInfo
    let packet: AppTrafficPacket?
    @State private var resolvedOverview: String? = nil

    var body: some View {
        Group {
            if let text = resolvedOverview {
                JSONTextView(text: text)
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(packet?.packetId ?? "")#\(packet?.revision ?? 0)") {
            resolvedOverview = nil
            let url = info.url
            let method = info.requestMethod?.rawValue
            let statusCode = info.statusCode
            let requestHeaders = info.requestHeaders
            let requestBodyBase64 = info.requestBody
            let responseDataBase64 = info.responseData
            let requestContentType = HTTPHeaders.value("Content-Type", in: info.requestHeaders)
            let responseContentType = HTTPHeaders.value("Content-Type", in: info.responseHeaders)
            let result = await Task.detached(priority: .userInitiated) {
                await resolveOverview(
                    url: url,
                    method: method,
                    statusCode: statusCode,
                    requestHeaders: requestHeaders,
                    requestBodyBase64: requestBodyBase64,
                    responseDataBase64: responseDataBase64,
                    requestContentType: requestContentType,
                    responseContentType: responseContentType
                )
            }.value
            resolvedOverview = result
        }
    }
    
    /// Builds the full overview string off the main thread. Takes only value types so it can run in Task.detached.
    func resolveOverview(
        url: String?,
        method: String?,
        statusCode: String?,
        requestHeaders: [String: String]?,
        requestBodyBase64: String?,
        responseDataBase64: String?,
        requestContentType: String? = nil,
        responseContentType: String? = nil
    ) -> String {
        
        var overviewText = ""
        overviewText += (method ?? "") + " " + (url ?? "") + "\n\n"
        
        if let code = statusCode, !code.isEmpty { overviewText += "Response Code: \(code)\n\n" }
        
        if let urlStr = url, let url = URL(string: urlStr),
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty {
            let params = items.map { "\($0.name): \($0.value ?? "")" }.joined(separator: "\n")
            overviewText += "URL Parameters:\n" + params + "\n\n"
        }
        
        if let h = requestHeaders, !h.isEmpty {
            let headerStr = h.keys.sorted().map { key in "\(key): \(h[key] ?? "")" }.joined(separator: "\n")
            overviewText += "Request Headers:\n" + headerStr + "\n\n"
        }
        
        let reqBodyResult = requestBodyBase64?.convertBase64ToPrettyJson(contentType: requestContentType) ?? .empty
        let reqBodyStr = reqBodyResult.bodyDisplayResultToOverviewString()
        if !reqBodyStr.isEmpty { overviewText += "Request Body:\n" + reqBodyStr + "\n\n" }
        
        let respBodyResult = responseDataBase64?.convertBase64ToPrettyJson(contentType: responseContentType) ?? .empty
        let respBodyStr = respBodyResult.bodyDisplayResultToOverviewString()
        if !respBodyStr.isEmpty { overviewText += "Response Body:\n" + respBodyStr }
        
        return overviewText
    }
}
