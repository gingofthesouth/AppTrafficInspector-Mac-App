//
//  MCPJSONRPCHandler.swift
//  App Traffic Inspector
//
//  JSON-RPC 2.0 dispatch for MCP: initialize, tools/list, tools/call, ping.
//

import Foundation

enum MCPJSONRPCHandler {
    static let protocolVersion = "2025-11-25"
    static let serverName = "AppTrafficInspector"
    static let serverVersion = "1.0.0"

    enum RPCError: Error, Sendable {
        case invalidRequest(String)
        case methodNotFound(String)
        case invalidParams(String)
        case internalError(String)
    }

    /// Process JSON-RPC body and return response dict (or nil for notification).
    static func handle(
        body: Data,
        sessionId: String?,
        toolRegistry: MCPToolRegistry
    ) async -> (response: [String: Any]?, statusCode: Int) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = json["method"] as? String else {
            return (errorResponse(id: nil, code: -32600, message: "Invalid Request"), 400)
        }
        let id = json["id"]
        let params = json["params"] as? [String: Any]

        do {
            switch method {
            case "initialize":
                let result = handleInitialize(params: params)
                return (successResponse(id: id, result: result), 200)
            case "notifications/initialized":
                return (nil, 202)
            case "tools/list":
                let list = toolRegistry.listTools()
                let result = ["tools": list] as [String: Any]
                return (successResponse(id: id, result: result), 200)
            case "tools/call":
                let result = try await handleToolsCall(params: params, registry: toolRegistry)
                return (successResponse(id: id, result: result), 200)
            case "ping":
                return (successResponse(id: id, result: [:] as [String: Any]), 200)
            default:
                throw RPCError.methodNotFound("Method not found: \(method)")
            }
        } catch let e as RPCError {
            let (code, message): (Int, String) = switch e {
            case .invalidRequest(let m): (-32600, m)
            case .methodNotFound(let m): (-32601, m)
            case .invalidParams(let m): (-32602, m)
            case .internalError(let m): (-32603, m)
            }
            return (errorResponse(id: id, code: code, message: message), 200)
        } catch {
            return (errorResponse(id: id, code: -32603, message: error.localizedDescription), 200)
        }
    }

    private static func handleInitialize(params: [String: Any]?) -> [String: Any] {
        [
            "protocolVersion": protocolVersion,
            "capabilities": [
                "tools": [String: Any](),
                "notifications": [
                    "traffic/packetAdded": [:] as [String: Any],
                    "traffic/packetUpdated": [:] as [String: Any],
                    "traffic/projectAdded": [:] as [String: Any],
                    "traffic/deviceAdded": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "serverInfo": [
                "name": serverName,
                "version": serverVersion
            ] as [String: Any]
        ] as [String: Any]
    }

    private static func handleToolsCall(params: [String: Any]?, registry: MCPToolRegistry) async throws -> [String: Any] {
        guard let params = params,
              let name = params["name"] as? String else {
            throw RPCError.invalidParams("Missing name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let toolResult = try await registry.callTool(name: name, arguments: arguments)
        return [
            "content": toolResult.content,
            "isError": toolResult.isError
        ] as [String: Any]
    }

    private static func successResponse(id: Any?, result: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id = id { out["id"] = id }
        return out
    }

    private static func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        var out: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message] as [String: Any]
        ]
        if let id = id { out["id"] = id }
        return out
    }
}
