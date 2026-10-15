//
//  AppTrafficPacket.swift
//  App Traffic Inspector
//

import Cocoa
import Combine

class AppTrafficPacket: Codable, Hashable, ObservableObject {
    var packetId: String?

    var requestInfo: AppTrafficRequestInfo?
    var project: AppTrafficProjectModel?
    var device: AppTrafficPacketDevice?

    /// Set on transactions created by in-app Replay; never present on the producer wire format.
    var replayOfPacketId: String?
    /// Transport error from a failed replay (no HTTP response was received).
    var replayError: String?

    var isReplay: Bool { replayOfPacketId != nil }

    /// Incremented whenever a later wire packet with the same `packetId` updates this transaction.
    /// Views key async work on it because identity-based equality hides in-place updates from SwiftUI.
    private(set) var revision = 0

    let objectWillChange = ObservableObjectPublisher()

    /// Applies a later packet for the same transaction without regressing already-received state.
    func applyUpdate(from newer: AppTrafficPacket) {
        objectWillChange.send()
        if let incoming = newer.requestInfo {
            requestInfo = requestInfo.map { $0.merged(with: incoming) } ?? incoming
        }
        revision += 1
    }

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
