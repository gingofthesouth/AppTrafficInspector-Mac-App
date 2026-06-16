//
//  NetworkInterfaceDetector.swift
//  App Traffic Inspector
//

import Foundation
import SystemConfiguration
import Darwin

struct NetworkInterface {
    let name: String
    let type: InterfaceType
    var ipv4Addresses: [String]
    var ipv6Addresses: [String]
    
    enum InterfaceType {
        case ethernet
        case wifi
        case other
        
        static func fromInterfaceName(_ name: String) -> InterfaceType {
            if name.hasPrefix("en") {
                return name == "en0" ? .wifi : .ethernet
            } else if name.hasPrefix("utun") || name.hasPrefix("ppp") {
                return .other
            }
            return .other
        }
    }
}

class NetworkInterfaceDetector {

    static func getActiveInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []

        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let list = interfaceList else { return [] }
        defer { freeifaddrs(list) }

        var interfaceGroups: [String: (ipv4: [String], ipv6: [String])] = [:]

        var ptr: UnsafeMutablePointer<ifaddrs>? = list
        while let current = ptr {
            let cur = current.pointee
            defer { ptr = cur.ifa_next }

            let name = String(cString: cur.ifa_name)
            guard let addr = cur.ifa_addr else { continue }

            // Skip loopback and virtual interfaces
            if name.hasPrefix("lo") || name.contains("docker") ||
               name.hasPrefix("bridge") || name.hasPrefix("veth") {
                continue
            }

            if let address = getIPAddress(from: addr) {
                var group = interfaceGroups[name] ?? (ipv4: [], ipv6: [])

                if addr.pointee.sa_family == UInt8(AF_INET) {
                    if !isLoopback(address) && !isLinkLocal(address) {
                        group.ipv4.append(address)
                    }
                } else if addr.pointee.sa_family == UInt8(AF_INET6) {
                    // Filter out link-local addresses for Bonjour
                    if !address.hasPrefix("fe80::") {
                        group.ipv6.append(address)
                    }
                }

                interfaceGroups[name] = group
            }
        }

        for (name, addresses) in interfaceGroups {
            let type = NetworkInterface.InterfaceType.fromInterfaceName(name)

            if !addresses.ipv4.isEmpty || !addresses.ipv6.isEmpty {
                let networkInterface = NetworkInterface(
                    name: name,
                    type: type,
                    ipv4Addresses: addresses.ipv4.filter { !isLoopback($0) && !isLinkLocal($0) },
                    ipv6Addresses: addresses.ipv6.filter { !$0.hasPrefix("fe80::") }
                )

                if !networkInterface.ipv4Addresses.isEmpty || !networkInterface.ipv6Addresses.isEmpty {
                    interfaces.append(networkInterface)
                }
            }
        }

        return interfaces
    }

    static func getPreferredInterface() -> NetworkInterface? {
        let interfaces = getActiveInterfaces()

        if let ethernetInterface = interfaces.first(where: { $0.type == .ethernet }) {
            return ethernetInterface
        }

        if let wifiInterface = interfaces.first(where: { $0.type == .wifi }) {
            return wifiInterface
        }

        return interfaces.first
    }
    
    private static func getIPAddress(from addr: UnsafeMutablePointer<sockaddr>?) -> String? {
        guard let addr = addr else { return nil }
        
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        
        if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname,
                      socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
            let bytes = hostname.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        }
        
        return nil
    }
    
    private static func isLoopback(_ address: String) -> Bool {
        return address == "127.0.0.1" || address.hasPrefix("::1")
    }
    
    private static func isLinkLocal(_ address: String) -> Bool {
        return address.hasPrefix("169.254.")
    }
}

private func getnameinfo(_ sa: UnsafePointer<sockaddr>?, _ salen: socklen_t,
                        _ hostname: UnsafeMutablePointer<CChar>, _ hostlen: socklen_t,
                        _ serv: UnsafeMutablePointer<CChar>?, _ servlen: socklen_t,
                        _ flags: Int32) -> Int32 {
    return Darwin.getnameinfo(sa, salen, hostname, hostlen, serv, servlen, flags)
}
