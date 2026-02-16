//
//  TrafficTools.swift
//  App Traffic Inspector
//

import Foundation

struct ListProjectsTool: MCPTool {
    let name = "list_projects"
    let description = "List all connected projects with device and packet counts."
    var inputSchema: [String: Any] { ["type": "object", "properties": [:] as [String: Any]] }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let data = await MainActor.run {
            let projects = AppTrafficController.shared.projects
            let list = projects.map { proj -> [String: Any] in
                let devices = proj.devices
                let packetCount = devices.reduce(0) { $0 + $1.packets.count }
                return [
                    "name": proj.projectName ?? "Unnamed",
                    "deviceCount": devices.count,
                    "packetCount": packetCount
                ] as [String: Any]
            }
            let json = ["projects": list] as [String: Any]
            return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct ListDevicesTool: MCPTool {
    let name = "list_devices"
    let description = "List devices for a project by name."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["projectName": ["type": "string", "description": "Project name"] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let projectName = arguments["projectName"] as? String
        let data = await MainActor.run {
            let projects = AppTrafficController.shared.projects
            guard let project = projects.first(where: { $0.projectName == projectName }) ?? projects.first else {
                return "{\"devices\":[]}".data(using: .utf8) ?? Data()
            }
            let devices = project.devices.map { dev -> [String: Any] in
                [
                    "deviceId": dev.deviceId ?? "",
                    "deviceName": dev.deviceName ?? "Device",
                    "deviceDescription": dev.deviceDescription ?? "",
                    "packetCount": dev.packets.count
                ] as [String: Any]
            }
            let json = ["devices": devices] as [String: Any]
            return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct ListPacketsTool: MCPTool {
    let name = "list_packets"
    let description = "List packet summaries for a project and device, with optional filters (method, statusCode, urlPattern, limit, offset)."
    var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "projectName": ["type": "string"] as [String: Any],
                "deviceId": ["type": "string"] as [String: Any],
                "method": ["type": "string"] as [String: Any],
                "statusCode": ["type": "string"] as [String: Any],
                "urlPattern": ["type": "string"] as [String: Any],
                "limit": ["type": "integer"] as [String: Any],
                "offset": ["type": "integer"] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let projectName = arguments["projectName"] as? String
        let deviceId = arguments["deviceId"] as? String
        let method = arguments["method"] as? String
        let statusCode = arguments["statusCode"] as? String
        let urlPattern = arguments["urlPattern"] as? String
        let limit = arguments["limit"] as? Int ?? 50
        let offset = arguments["offset"] as? Int ?? 0

        let data = await MainActor.run {
            let projects = AppTrafficController.shared.projects
            guard let project = projects.first(where: { $0.projectName == projectName }) ?? projects.first,
                  let device = deviceId != nil
                    ? project.devices.first(where: { $0.deviceId == deviceId })
                    : project.devices.first
            else {
                return "{\"packets\":[],\"total\":0}".data(using: .utf8) ?? Data()
            }
            var packets = device.packets
            if let m = method, !m.isEmpty {
                packets = packets.filter { $0.requestInfo?.requestMethod?.rawValue.lowercased().contains(m.lowercased()) ?? false }
            }
            if let s = statusCode, !s.isEmpty {
                packets = packets.filter { $0.requestInfo?.statusCode?.contains(s) ?? false }
            }
            if let u = urlPattern, !u.isEmpty {
                packets = packets.filter { $0.requestInfo?.url?.contains(u) ?? false }
            }
            let total = packets.count
            let slice = Array(packets.dropFirst(offset).prefix(limit))
            let list = slice.map { p -> [String: Any] in
                [
                    "packetId": p.packetId ?? "",
                    "method": p.requestInfo?.requestMethod?.rawValue ?? "",
                    "url": p.requestInfo?.url ?? "",
                    "statusCode": p.requestInfo?.statusCode ?? "",
                    "startDate": p.requestInfo?.startDate?.timeIntervalSince1970 ?? 0
                ] as [String: Any]
            }
            let json: [String: Any] = ["packets": list, "total": total]
            return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct GetPacketDetailTool: MCPTool {
    let name = "get_packet_detail"
    let description = "Get full detail for a packet by packetId. Applies privacy redaction."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["packetId": ["type": "string", "description": "Packet ID"] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        guard let packetId = arguments["packetId"] as? String else {
            return .text("{\"error\":\"Missing packetId\"}", isError: true)
        }
        let data = await MainActor.run { () -> Data? in
            let controller = AppTrafficController.shared
            guard let packet = controller.projects.flatMap(\.devices).flatMap(\.packets).first(where: { $0.packetId == packetId }),
                  let info = packet.requestInfo else { return nil }
            let mode = TrafficRedactor.currentMode()
            let redacted = TrafficRedactor.redactRequestInfo(
                url: info.url,
                requestHeaders: info.requestHeaders,
                requestBody: info.requestBody,
                responseHeaders: info.responseHeaders,
                responseData: info.responseData,
                mode: mode
            )
            var detail: [String: Any] = [
                "packetId": packet.packetId ?? "",
                "url": redacted.url ?? "",
                "requestMethod": info.requestMethod?.rawValue ?? "",
                "statusCode": info.statusCode ?? "",
                "requestHeaders": redacted.requestHeaders,
                "responseHeaders": redacted.responseHeaders,
                "requestBody": redacted.requestBody ?? "",
                "responseData": redacted.responseData ?? "",
                "startDate": info.startDate?.timeIntervalSince1970 ?? 0,
                "endDate": info.endDate?.timeIntervalSince1970 ?? 0
            ]
            detail["_redactionSummary"] = [
                "headersRedacted": redacted.headersRedacted,
                "bodyFieldsRedacted": redacted.bodyFieldsRedacted,
                "privacyMode": mode.rawValue
            ] as [String: Any]
            return try? JSONSerialization.data(withJSONObject: detail)
        }
        guard let data = data else { return .text("{\"error\":\"Packet not found\"}", isError: true) }
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct SearchPacketsTool: MCPTool {
    let name = "search_packets"
    let description = "Full-text search across URLs, headers, and bodies. Returns matching packet summaries."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["query": ["type": "string"] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        let query = (arguments["query"] as? String)?.lowercased() ?? ""
        if query.isEmpty {
            return .text("{\"packets\":[],\"total\":0}")
        }
        let data = await MainActor.run {
            let projects = AppTrafficController.shared.projects
            var list: [[String: Any]] = []
            for project in projects {
                for device in project.devices {
                    for packet in device.packets {
                        if Self.matchesQuery(packet, query: query) {
                            list.append([
                                "packetId": packet.packetId ?? "",
                                "method": packet.requestInfo?.requestMethod?.rawValue ?? "",
                                "url": packet.requestInfo?.url ?? "",
                                "statusCode": packet.requestInfo?.statusCode ?? ""
                            ] as [String: Any])
                        }
                    }
                }
            }
            let json: [String: Any] = ["packets": list, "total": list.count]
            return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        }
        return .text(String(data: data, encoding: .utf8) ?? "{}")
    }

    private static func matchesQuery(_ packet: AppTrafficPacket, query: String) -> Bool {
        if packet.requestInfo?.url?.lowercased().contains(query) == true { return true }
        for (k, v) in packet.requestInfo?.requestHeaders ?? [:] {
            if k.lowercased().contains(query) || v.lowercased().contains(query) { return true }
        }
        for (k, v) in packet.requestInfo?.responseHeaders ?? [:] {
            if k.lowercased().contains(query) || v.lowercased().contains(query) { return true }
        }
        if let b64 = packet.requestInfo?.requestBody,
           let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
           let str = String(data: data, encoding: .utf8), str.lowercased().contains(query) { return true }
        if let b64 = packet.requestInfo?.responseData,
           let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
           let str = String(data: data, encoding: .utf8), str.lowercased().contains(query) { return true }
        return false
    }
}

struct GetPacketCurlTool: MCPTool {
    let name = "get_packet_curl"
    let description = "Get cURL command for a packet by packetId."
    var inputSchema: [String: Any] {
        ["type": "object", "properties": ["packetId": ["type": "string"] as [String: Any]] as [String: Any]]
    }

    func execute(arguments: [String: Any]) async throws -> MCPToolResult {
        guard let packetId = arguments["packetId"] as? String else {
            return .text("Missing packetId", isError: true)
        }
        let curl = await MainActor.run {
            guard let packet = AppTrafficController.shared.projects.flatMap(\.devices).flatMap(\.packets).first(where: { $0.packetId == packetId }),
                  let info = packet.requestInfo else { return "(packet not found)" }
            let c = PacketFormatting.curlString(for: info)
            return c.isEmpty ? "(no URL)" : c
        }
        return .text(curl)
    }
}
