//
//  MCPActivityLog.swift
//  App Traffic Inspector
//
//  In-memory log of MCP server activity for the MCP Console UI.
//

import Foundation
import SwiftUI

enum MCPActivityDirection {
    case inbound
    case outbound
    case internal_
}

@MainActor
@Observable
final class MCPActivityLog {
    static let shared = MCPActivityLog()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let direction: MCPActivityDirection
        let summary: String
        var detail: String?
        var statusCode: Int?
    }

    private let maxEntries = 500
    private(set) var entries: [Entry] = []

    private init() {}

    func log(direction: MCPActivityDirection, summary: String, detail: String? = nil, statusCode: Int? = nil) {
        let entry = Entry(timestamp: Date(), direction: direction, summary: summary, detail: detail, statusCode: statusCode)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        DevLogger.logInfo(message: "[\(summary)] \(detail ?? "")")
    }

    func clear() {
        entries.removeAll()
    }
}
