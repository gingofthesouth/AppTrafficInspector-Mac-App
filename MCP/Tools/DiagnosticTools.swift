//
//  DiagnosticTools.swift
//  App Traffic Inspector
//

import Foundation

struct GetAppInfoTool: MCPTool {
    let name = "get_app_info"
    let description = "Return app version, build number, uptime, total packet count."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    private nonisolated(unsafe) static var launchTime = Date()

    static func setLaunchTime(_ date: Date) {
        launchTime = date
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let (version, build, totalPackets) = await MainActor.run {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let controller = AppTrafficController.shared
            let total = controller.projects.reduce(0) { sum, proj in
                sum + proj.devices.reduce(0) { $0 + $1.packets.count }
            }
            return (v, b, total)
        }
        let uptime = Int(-Self.launchTime.timeIntervalSinceNow)
        let json: [String: Any] = [
            "version": version,
            "build": build,
            "uptimeSeconds": uptime,
            "totalPacketCount": totalPackets
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct GetRedactionSettingsTool: MCPTool {
    let name = "get_redaction_settings"
    let description = "Return current redaction mode and custom field names."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let mode = TrafficRedactor.currentMode()
        let custom = TrafficRedactor.customRedactionFieldNames()
        let json: [String: Any] = [
            "mode": mode.rawValue,
            "customFieldNames": custom
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct SetRedactionModeTool: MCPTool {
    let name = "set_redaction_mode"
    let description = "Set redaction mode: strict, moderate, or off. Persists to UserDefaults."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["mode": ["type": "string", "enum": ["strict", "moderate", "off"]] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        guard let raw = arguments["mode"] as? String,
              let mode = RedactionMode(rawValue: raw) else {
            return .text("Invalid or missing mode (use strict, moderate, or off)", isError: true)
        }
        TrafficRedactor.setMode(mode)
        return .text("{\"mode\":\"\(mode.rawValue)\"}")
    }
}
