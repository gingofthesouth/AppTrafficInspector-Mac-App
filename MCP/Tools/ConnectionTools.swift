//
//  ConnectionTools.swift
//  App Traffic Inspector
//

import Foundation
import Network

struct GetServerStatusTool: MCPTool {
    let name = "get_server_status"
    let description = "Return listener state, port, Bonjour name, active connection count, selected interface."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let publisher = await MainActor.run { AppTrafficController.shared.publisher }
        let state = publisher.listenerState
        let connections = publisher.activeConnections
        let port = AppTrafficConfiguration.netServicePort
        let bonjourName = AppTrafficConfiguration.netServiceName
        let interface = await MainActor.run {
            NetworkInterfaceDetector.getPreferredInterface()
        }
        var result: [String: Any] = [
            "listenerState": state?.description ?? "unknown",
            "port": port,
            "bonjourServiceName": bonjourName,
            "activeConnectionCount": connections.count
        ]
        if let iface = interface {
            result["interfaceName"] = iface.name
            result["interfaceType"] = String(describing: iface.type)
            result["ipv4Addresses"] = iface.ipv4Addresses
            result["ipv6Addresses"] = iface.ipv6Addresses
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

extension NWListener.State {
    var description: String {
        switch self {
        case .ready: return "ready"
        case .waiting: return "waiting"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }
}

struct ListConnectionsTool: MCPTool {
    let name = "list_connections"
    let description = "List active TCP connections (remote endpoint, state)."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let publisher = await MainActor.run { AppTrafficController.shared.publisher }
        let connections = publisher.activeConnections
        let list = connections.enumerated().map { idx, conn -> [String: Any] in
            [
                "index": idx,
                "state": connectionStateString(conn.state)
            ] as [String: Any]
        }
        let json = ["connections": list] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: json)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func connectionStateString(_ state: NWConnection.State) -> String {
        switch state {
        case .ready: return "ready"
        case .waiting: return "waiting"
        case .preparing: return "preparing"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        @unknown default: return "unknown"
        }
    }
}

struct GetNetworkInterfacesTool: MCPTool {
    let name = "get_network_interfaces"
    let description = "List detected network interfaces with type and addresses."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let interfaces = NetworkInterfaceDetector.getActiveInterfaces()
        let list = interfaces.map { iface -> [String: Any] in
            [
                "name": iface.name,
                "type": String(describing: iface.type),
                "ipv4Addresses": iface.ipv4Addresses,
                "ipv6Addresses": iface.ipv6Addresses
            ] as [String: Any]
        }
        let json = ["interfaces": list] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: json)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct GetErrorLogTool: MCPTool {
    let name = "get_error_log"
    let description = "Return recent DevLogger entries (ring buffer)."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let entries = DevLogger.recentEntries
        let json = ["entries": entries] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: json)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}
