//
//  BonjourSingleInterfaceRegistrar.swift
//  App Traffic Inspector
//
//  Registers the Bonjour service on a single interface only (e.g. en0) so
//  discovery returns only that interface's IP (e.g. 192.168.1.69), not
//  bridge/virtual interfaces (e.g. 192.168.215.0).
//

import Foundation
import Darwin

// C API from dns_sd (link framework dns_sd in the target)
private let kDNSServiceInterfaceIndexAny: UInt32 = 0
private let kDNSServiceInterfaceIndexLocalOnly: UInt32 = 0x7FFF_FFFF

private typealias DNSServiceRef = OpaquePointer
private typealias DNSServiceFlags = UInt32
private typealias DNSServiceErrorType = Int32

private typealias DNSServiceRegisterReply = @convention(c) (
    DNSServiceRef?, DNSServiceFlags, DNSServiceErrorType,
    UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?
) -> Void

@_silgen_name("DNSServiceRegister")
private func DNSServiceRegister(
    _ sdRef: UnsafeMutablePointer<DNSServiceRef?>,
    _ flags: DNSServiceFlags,
    _ interfaceIndex: UInt32,
    _ name: UnsafePointer<CChar>,
    _ regtype: UnsafePointer<CChar>,
    _ domain: UnsafePointer<CChar>,
    _ host: UnsafePointer<CChar>?,
    _ port: UInt16,
    _ txtLen: UInt16,
    _ txtRecord: UnsafeRawPointer?,
    _ callBack: DNSServiceRegisterReply?,
    _ context: UnsafeMutableRawPointer?
) -> DNSServiceErrorType

@_silgen_name("DNSServiceRefDeallocate")
private func DNSServiceRefDeallocate(_ sdRef: DNSServiceRef)

@_silgen_name("DNSServiceRefSockFD")
private func DNSServiceRefSockFD(_ sdRef: DNSServiceRef) -> Int32

@_silgen_name("DNSServiceProcessResult")
private func DNSServiceProcessResult(_ sdRef: DNSServiceRef) -> DNSServiceErrorType

/// Registers a Bonjour service on a single network interface so only that interface's
/// address(es) are advertised. Call `stop()` when done.
final class BonjourSingleInterfaceRegistrar {
    private var serviceRef: DNSServiceRef?
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "BonjourSingleInterfaceRegistrar")

    /// - Parameters:
    ///   - interfaceName: e.g. "en0" (use if_nametoindex to restrict to this interface only)
    ///   - name: Service name
    ///   - type: e.g. "_AppTraffic._tcp"
    ///   - domain: Empty string for default
    ///   - port: Port in host byte order
    /// - Returns: true if registration was started (callback may still report failure)
    func start(interfaceName: String, name: String, type: String, domain: String, port: UInt16) -> Bool {
        let ifIndex = interfaceName.withCString { if_nametoindex($0) }
        guard ifIndex != 0 else { return false }
        return start(interfaceIndex: ifIndex, name: name, type: type, domain: domain, port: port)
    }

    /// Interface index for peer-to-peer (AWDL) registration (kDNSServiceInterfaceIndexP2P, -3).
    static let peerToPeerInterfaceIndex = UInt32(bitPattern: -3)

    func start(interfaceIndex ifIndex: UInt32, name: String, type: String, domain: String, port: UInt16) -> Bool {
        stop()

        var ref: DNSServiceRef?
        let portBigEndian = port.bigEndian
        let reply: DNSServiceRegisterReply = { _, _, errorCode, _, _, _, _ in
            guard errorCode == 0 else {
                print("BonjourSingleInterfaceRegistrar: DNSServiceRegister callback error \(errorCode)")
                return
            }
            print("Bonjour published on interface only (single-interface registration)")
        }

        let err = name.withCString { nameC in
            type.withCString { typeC in
                (domain.isEmpty ? "" : domain).withCString { domainC in
                    DNSServiceRegister(
                        &ref,
                        0,
                        ifIndex,
                        nameC,
                        typeC,
                        domainC,
                        nil,
                        portBigEndian,
                        0,
                        nil,
                        reply,
                        nil
                    )
                }
            }
        }

        guard err == 0, let sdRef = ref else {
            print("BonjourSingleInterfaceRegistrar: DNSServiceRegister failed \(err)")
            return false
        }

        serviceRef = sdRef
        let fd = DNSServiceRefSockFD(sdRef)
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        readSource.setEventHandler { [weak self] in
            guard let self = self, let ref = self.serviceRef else { return }
            _ = DNSServiceProcessResult(ref)
        }
        readSource.resume()
        source = readSource
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        if let ref = serviceRef {
            DNSServiceRefDeallocate(ref)
            serviceRef = nil
        }
    }

    deinit {
        stop()
    }
}
