//
//  MCPToolRegistry.swift
//  App Traffic Inspector
//
//  Tool registration and dispatch for MCP tools/list and tools/call.
//

import Foundation

struct MCPToolResult: Sendable {
    let content: [[String: String]]
    let isError: Bool
    static func text(_ string: String, isError: Bool = false) -> MCPToolResult {
        MCPToolResult(content: [["type": "text", "text": string]], isError: isError)
    }
}

protocol MCPTool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any] { get }
    func execute(arguments: [String: Any]) async throws -> MCPToolResult
}

final class MCPToolRegistry: @unchecked Sendable {
    /// Written only at startup on main thread; read from MCP request handler.
    private nonisolated(unsafe) var tools: [String: any MCPTool] = [:]

    func register(_ tool: any MCPTool) {
        tools[tool.name] = tool
    }

    func listTools() -> [[String: Any]] {
        tools.values.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.inputSchema
            ] as [String: Any]
        }
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPToolResult {
        guard let tool = tools[name] else {
            throw MCPJSONRPCHandler.RPCError.methodNotFound("Unknown tool: \(name)")
        }
        return try await tool.execute(arguments: arguments)
    }
}
