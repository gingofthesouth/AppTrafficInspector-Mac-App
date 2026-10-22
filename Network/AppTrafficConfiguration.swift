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
    /// Also advertise and accept over peer-to-peer Wi-Fi (AWDL) so discovery works on networks that block mDNS.
    static var peerToPeerEnabled: Bool {
        UserDefaults.standard.object(forKey: "peerToPeerEnabled") as? Bool ?? true
    }
    static let portString: String = String(netServicePort)
    static let maximumTransactionBytes = 25 * 1024 * 1024
}
