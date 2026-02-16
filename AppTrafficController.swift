//
//  AppTrafficController.swift
//  App Traffic Inspector
//

import Cocoa

enum AddPacketResult {
    case updated
    case added
    case addedWithNewDevice(deviceId: String, deviceName: String)
    case addedWithNewProject(projectName: String)
}

struct AppTrafficNotifications {
    
    static let didGetPacket = NSNotification.Name("DidGetPacket")
    static let didUpdatePacket = NSNotification.Name("DidUpdatePacket")
    static let didSelectProject = NSNotification.Name("DidSelectProject")
    static let didSelectDevice = NSNotification.Name("DidSelectDevice")
    static let didSelectPacket = NSNotification.Name("DidSelectPacket")
}

@MainActor
final class AppTrafficController: NSObject, AppTrafficPublisherDelegate {
    
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
    
    private func packetEventParams(_ packet: AppTrafficPacket) -> (projectName: String, deviceId: String, deviceName: String, packetId: String, method: String, url: String, statusCode: String) {
        (
            packet.project?.projectName ?? "",
            packet.device?.deviceId ?? "",
            packet.device?.deviceName ?? "",
            packet.packetId ?? "",
            packet.requestInfo?.requestMethod?.rawValue ?? "",
            packet.requestInfo?.url ?? "",
            packet.requestInfo?.statusCode ?? ""
        )
    }

    func didGetPacket(publisher: AppTrafficPublisher, packet: AppTrafficPacket) {
        let result = self.addPacket(newPacket: packet)
        let params = packetEventParams(packet)

        switch result {
        case .updated:
            NotificationCenter.default.post(name: AppTrafficNotifications.didUpdatePacket, object: nil, userInfo: ["packet": packet])
            TrafficEventBus.shared.emit(.packetUpdated(projectName: params.projectName, deviceId: params.deviceId, packetId: params.packetId, method: params.method, url: params.url, statusCode: params.statusCode))
        case .added:
            NotificationCenter.default.post(name: AppTrafficNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            TrafficEventBus.shared.emit(.packetAdded(projectName: params.projectName, deviceId: params.deviceId, packetId: params.packetId, method: params.method, url: params.url, statusCode: params.statusCode))
            self.checkInitialSelection()
        case .addedWithNewDevice(let deviceId, let deviceName):
            NotificationCenter.default.post(name: AppTrafficNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            TrafficEventBus.shared.emit(.deviceAdded(projectName: params.projectName, deviceId: deviceId, deviceName: deviceName))
            TrafficEventBus.shared.emit(.packetAdded(projectName: params.projectName, deviceId: params.deviceId, packetId: params.packetId, method: params.method, url: params.url, statusCode: params.statusCode))
            self.checkInitialSelection()
        case .addedWithNewProject(let projectName):
            NotificationCenter.default.post(name: AppTrafficNotifications.didGetPacket, object: nil, userInfo: ["packet": packet])
            TrafficEventBus.shared.emit(.projectAdded(projectName: projectName))
            TrafficEventBus.shared.emit(.packetAdded(projectName: params.projectName, deviceId: params.deviceId, packetId: params.packetId, method: params.method, url: params.url, statusCode: params.statusCode))
            self.checkInitialSelection()
        }
    }

    @discardableResult
    func addPacket(newPacket: AppTrafficPacket) -> AddPacketResult {
        for project in self.projects {
            if project.projectName == newPacket.project?.projectName {
                return project.addPacket(newPacket: newPacket)
            }
        }

        let project = AppTrafficProject()
        project.projectName = newPacket.project?.projectName
        _ = project.addPacket(newPacket: newPacket)
        self.projects.append(project)
        if self.projects.count == 1 {
            self.selectedProject = self.projects.first
        }
        return .addedWithNewProject(projectName: newPacket.project?.projectName ?? "")
    }
    
    
    func checkInitialSelection() {
        if self.selectedProject?.selectedDevice?.packets.count == 1 {
            self.selectedProject?.selectedDevice?.notifyPacketSelection()
        }
    }
}
