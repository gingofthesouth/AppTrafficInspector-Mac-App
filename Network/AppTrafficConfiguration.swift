//
//  AppTrafficConfiguration.swift
//  App Traffic Inspector
//

import Cocoa

class AppTrafficConfiguration: NSObject {

    static let netServiceDomain: String = ""
    static let netServiceType: String = "_AppTraffic._tcp"
    static var netServiceName: String {
        // Use the computer's name as default
        return ProcessInfo.processInfo.hostName.components(separatedBy: ".").first ?? "AppTraffic"
    }
    static let netServicePort: UInt16 = 43435
    static let portString: String = String(netServicePort)
}
