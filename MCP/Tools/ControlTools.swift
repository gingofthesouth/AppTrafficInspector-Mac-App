//
//  ControlTools.swift
//  App Traffic Inspector
//
//  DEBUG-only mutation tools: restart_listener, clear_packets, inject_test_packet.
//

import Foundation

#if DEBUG
struct RestartListenerTool: MCPTool {
    let name = "restart_listener"
    let description = "Restart the traffic listener (DEBUG only)."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        await MainActor.run {
            AppTrafficController.shared.publisher.startPublishing()
        }
        return .text("{\"status\":\"restarting\"}")
    }
}

struct ClearPacketsTool: MCPTool {
    let name = "clear_packets"
    let description = "Clear packets for the currently selected device (DEBUG only)."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        await MainActor.run {
            AppTrafficController.shared.selectedProject?.selectedDevice?.clear()
        }
        return .text("{\"status\":\"cleared\"}")
    }
}

struct InjectTestPacketTool: MCPTool {
    let name = "inject_test_packet"
    let description = "Inject a synthetic packet (JSON body) for testing (DEBUG only)."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["packetJson": ["type": "string", "description": "JSON string of AppTrafficPacket"] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        guard let jsonStr = arguments["packetJson"] as? String,
              let data = jsonStr.data(using: .utf8) else {
            return .text("Missing packetJson", isError: true)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let result: Result<(Bool, String), Error> = await MainActor.run {
            do {
                let packet = try decoder.decode(AppTrafficPacket.self, from: data)
                let addResult = AppTrafficController.shared.addPacket(newPacket: packet)
                let added: Bool = if case .updated = addResult { false } else { true }
                return .success((added, packet.packetId ?? ""))
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .success((let added, let packetId)):
            return .text("{\"injected\":\(added),\"packetId\":\"\(packetId)\"}")
        case .failure(let error):
            return .text("{\"error\":\"\(error.localizedDescription)\"}", isError: true)
        }
    }
}
#endif
