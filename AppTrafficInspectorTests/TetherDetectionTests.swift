//
//  TetherDetectionTests.swift
//  AppTrafficInspectorTests
//

@testable import App_Traffic_Inspector
import Testing

struct TetherDetectionTests {

    @Test(arguments: ["172.20.10.2", "172.20.10.15", "172.20.10.1"])
    func recognisesHotspotAddresses(address: String) {
        #expect(NetworkInterfaceDetector.isTetherAddress(address))
    }

    @Test(arguments: ["172.20.10.16", "172.20.11.2", "192.168.1.5", "10.0.0.1", "garbage"])
    func rejectsOtherAddresses(address: String) {
        #expect(!NetworkInterfaceDetector.isTetherAddress(address))
    }

    @Test func picksOnlyTetherInterfaces() {
        let wifi = NetworkInterface(name: "en0", type: .wifi, ipv4Addresses: ["10.1.1.5"], ipv6Addresses: [])
        let usb = NetworkInterface(name: "en7", type: .ethernet, ipv4Addresses: ["172.20.10.2"], ipv6Addresses: [])
        #expect(NetworkInterfaceDetector.tetherInterfaces(in: [wifi, usb]).map(\.name) == ["en7"])
    }
}
