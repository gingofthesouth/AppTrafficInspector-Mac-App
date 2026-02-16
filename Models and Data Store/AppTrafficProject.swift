//
//  AppTrafficProject.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficProject: NSObject {
    
    var projectName: String?
    
    var devices: [AppTrafficDevice] = []
    var selectedDevice: AppTrafficDevice? {
        didSet {
            NotificationCenter.default.post(name: AppTrafficNotifications.didSelectDevice, object: nil)
        }
    }
    
    @discardableResult
    func addPacket(newPacket: AppTrafficPacket) -> AddPacketResult {
        // Prefer match by deviceId; then coalesce by (projectName, deviceName) to avoid duplicate "connections"
        // when the client sends multiple deviceIds (e.g. multiple inspector instances or Bonjour resolving multiple times).
        for device in self.devices {
            if device.deviceId == newPacket.device?.deviceId {
                return device.addPacket(newPacket: newPacket) ? .added : .updated
            }
        }
        let sameName = newPacket.device?.deviceName
        let sameProject = newPacket.project?.projectName == self.projectName
        if sameProject, let name = sameName, !name.isEmpty {
            for device in self.devices where device.deviceName == name {
                device.deviceId = device.deviceId ?? newPacket.device?.deviceId
                return device.addPacket(newPacket: newPacket) ? .added : .updated
            }
        }

        let device = AppTrafficDevice()
        device.deviceId = newPacket.device?.deviceId
        device.deviceName = newPacket.device?.deviceName
        device.deviceDescription = newPacket.device?.deviceDescription
        device.addPacket(newPacket: newPacket)
        self.devices.append(device)

        if self.devices.count == 1 {
            self.selectedDevice = self.devices.first
        }
        return .addedWithNewDevice(
            deviceId: newPacket.device?.deviceId ?? "",
            deviceName: newPacket.device?.deviceName ?? ""
        )
    }
}
