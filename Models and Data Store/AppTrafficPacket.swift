//
//  AppTrafficPacket.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficPacket: Codable, Hashable {
    var packetId: String?

    var requestInfo: AppTrafficRequestInfo?
    var project: AppTrafficProjectModel?
    var device: AppTrafficPacketDevice?

    /// Set on transactions created by in-app Replay; never present on the producer wire format.
    var replayOfPacketId: String?
    /// Transport error from a failed replay (no HTTP response was received).
    var replayError: String?

    var isReplay: Bool { replayOfPacketId != nil }

    init() {}

    enum CodingKeys: String, CodingKey {
        case packetId, requestInfo, project, device
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    static func == (lhs: AppTrafficPacket, rhs: AppTrafficPacket) -> Bool {
        lhs === rhs
    }

    struct AppTrafficProjectModel: Codable {
        var projectName: String?
    }
    
    struct AppTrafficPacketDevice: Codable {
        var deviceId: String?
        var deviceName: String?
        var deviceDescription: String?
    }
}
