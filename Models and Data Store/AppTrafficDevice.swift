//
//  AppTrafficDevice.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficDevice: NSObject {
    static let maximumTransactionCount = 1_000
    static let maximumPayloadBytes = 250 * 1024 * 1024

    private let transactionCountLimit: Int
    private let payloadByteLimit: Int

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    var packets: [AppTrafficPacket] = []
    private(set) var selectedPacket: AppTrafficPacket?

    override init() {
        transactionCountLimit = Self.maximumTransactionCount
        payloadByteLimit = Self.maximumPayloadBytes
        super.init()
    }

    init(transactionCountLimit: Int, payloadByteLimit: Int) {
        self.transactionCountLimit = transactionCountLimit
        self.payloadByteLimit = payloadByteLimit
        super.init()
    }
    
    func select(packet: AppTrafficPacket?) {
        self.selectedPacket = packet
        self.notifyPacketSelection()
    }
    
    func notifyPacketSelection() {
        NotificationCenter.default.post(name: AppTrafficNotifications.didSelectPacket, object: nil)
    }
    
    @discardableResult
    func addPacket(newPacket: AppTrafficPacket) -> Bool {
        
        for packet in self.packets {
            
            if packet.packetId == newPacket.packetId {
                
                packet.applyUpdate(from: newPacket)
                return false
            }
        }
        
        self.packets.append(newPacket)
        
        if self.packets.count == 1 {
            
            self.selectedPacket = self.packets.first
        }

        enforceRetentionLimits()
        
        return true
    }

    private func enforceRetentionLimits() {
        var payloadBytes = packets.reduce(0) { $0 + $1.estimatedPayloadBytes }
        var selectionWasEvicted = false

        while packets.count > transactionCountLimit || payloadBytes > payloadByteLimit {
            let removed = packets.removeFirst()
            payloadBytes -= removed.estimatedPayloadBytes
            if removed === selectedPacket {
                selectionWasEvicted = true
            }
        }

        if selectionWasEvicted {
            selectedPacket = packets.last
            notifyPacketSelection()
        }
    }
    
    func clear() {
        
        self.packets.removeAll()
        self.select(packet: nil)
    }
}

private extension AppTrafficPacket {
    var estimatedPayloadBytes: Int {
        decodedByteCount(requestInfo?.requestBody) + decodedByteCount(requestInfo?.responseData)
    }

    func decodedByteCount(_ base64: String?) -> Int {
        guard let base64 else { return 0 }
        let padding = base64.suffix(2).prefix(while: { $0 == "=" }).count
        return max(0, base64.utf8.count / 4 * 3 - padding)
    }
}
