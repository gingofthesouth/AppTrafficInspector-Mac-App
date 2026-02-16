//
//  MCPServerStatus.swift
//  App Traffic Inspector
//

import Foundation
import SwiftUI

/// Shared status for MCP server running state. Updated by AppDelegate and MCPServer.
@MainActor
final class MCPServerStatus: ObservableObject {
    static let shared = MCPServerStatus()
    @Published var isMCPServerRunning = false
    @Published var activeSSESubscribers: Int = 0
    @Published var totalRequestsHandled: Int = 0
    @Published var lastRequestTime: Date?
    private init() {}
}
