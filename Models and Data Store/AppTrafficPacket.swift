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
