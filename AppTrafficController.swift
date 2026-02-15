//
//  AppTrafficController.swift
//  App Traffic Inspector
//

import Cocoa

struct AppTrafficNotifications {
    
    static let didGetPacket = NSNotification.Name("DidGetPacket")
    static let didUpdatePacket = NSNotification.Name("DidUpdatePacket")
    static let didSelectProject = NSNotification.Name("DidSelectProject")
    static let didSelectDevice = NSNotification.Name("DidSelectDevice")
    static let didSelectPacket = NSNotification.Name("DidSelectPacket")
}

class AppTrafficController: NSObject, AppTrafficPublisherDelegate {
    
    static let shared = AppTrafficController()
    
    var projects: [AppTrafficProject] = []
    var selectedProject: AppTrafficProject? {
        didSet {
            NotificationCenter.default.post(name: AppTrafficNotifications.didSelectProject, object: nil)
        }
    }
    
    var publisher = AppTrafficPublisher()
    
    override init() {
        
        super.init()
        self.publisher.delegate = self
        self.publisher.startPublishing()
        
    }
    
    func didGetPacket(publisher: AppTrafficPublisher, packet: AppTrafficPacket) {
        
        if self.addPacket(newPacket: packet) {
            NotificationCenter.default.post(name: AppTrafficNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            self.checkInitialSelection()
        }else{
            NotificationCenter.default.post(name: AppTrafficNotifications.didUpdatePacket, object: nil, userInfo: ["packet": packet])
        }
    }
    
    @discardableResult
    func addPacket(newPacket: AppTrafficPacket) -> Bool {
        
        for project in self.projects {
            
            if project.projectName == newPacket.project?.projectName {
                
                return project.addPacket(newPacket: newPacket)
            }
        }
        
        
        let project = AppTrafficProject()
        
        project.projectName = newPacket.project?.projectName
        project.addPacket(newPacket: newPacket)
        
        self.projects.append(project)
        
        
        
        if self.projects.count == 1 {
            
            self.selectedProject = self.projects.first
        }
        
        return true
    }
    
    
    func checkInitialSelection() {
        if self.selectedProject?.selectedDevice?.packets.count == 1 {
            self.selectedProject?.selectedDevice?.notifyPacketSelection()
        }
    }
}
