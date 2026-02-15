//
//  AppTrafficDevice.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficDevice: NSObject {

    var deviceId: String?
    var deviceName: String?
    var deviceDescription: String?
    
    var packets: [AppTrafficPacket] = []
    private(set) var selectedPacket: AppTrafficPacket?
    
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
                
                packet.requestInfo = newPacket.requestInfo
                return false
            }
        }
        
        self.packets.append(newPacket)
        
        if self.packets.count == 1 {
            
            self.selectedPacket = self.packets.first
        }
        
        return true
    }
    
    func clear() {
        
        self.packets.removeAll()
        self.select(packet: nil)
    }
}
