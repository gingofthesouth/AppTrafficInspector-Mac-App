//
//  App Traffic InspectorProjectController.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficProject: NSObject {
    
    var projectName: String?
    
    var deviceControllers: [AppTrafficDeviceController] = []
    var selectedDeviceController: AppTrafficDeviceController? {
        didSet {
            NotificationCenter.default.post(name: AppTrafficNotifications.didSelectDevice, object: nil)
        }
    }
    
    @discardableResult
    func addPacket(newPacket: AppTrafficPacket) -> Bool {
        
        for deviceController in self.deviceControllers {
            
            if deviceController.deviceId == newPacket.device?.deviceId {
                
                return deviceController.addPacket(newPacket: newPacket)
            }
        }
        
        let deviceController = AppTrafficDeviceController()
        
        deviceController.deviceId = newPacket.device?.deviceId
        deviceController.deviceName = newPacket.device?.deviceName
        deviceController.deviceDescription = newPacket.device?.deviceDescription
        
        deviceController.addPacket(newPacket: newPacket)
        
        self.deviceControllers.append(deviceController)
        
        if self.deviceControllers.count == 1 {
            
            self.selectedDeviceController = self.deviceControllers.first
        }
        
        return true
    }
}
