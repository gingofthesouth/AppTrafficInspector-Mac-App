//
//  PacketUpdateTests.swift
//  AppTrafficInspectorTests
//

@testable import App_Traffic_Inspector
import Combine
import Foundation
import Testing

struct PacketUpdateTests {

    private func decodePacket(_ json: String) throws -> AppTrafficPacket {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(AppTrafficPacket.self, from: Data(json.utf8))
    }

    private func packet(
        id: String = "p1",
        statusCode: String? = nil,
        responseData: String? = nil,
        endDate: Date? = nil
    ) -> AppTrafficPacket {
        let packet = AppTrafficPacket()
        packet.packetId = id
        packet.requestInfo = AppTrafficRequestInfo(
            url: "https://example.com/a",
            requestHeaders: ["Accept": "application/json"],
            requestMethod: .get,
            responseHeaders: statusCode == nil ? nil : ["Content-Type": "application/json"],
            responseData: responseData,
            statusCode: statusCode,
            startDate: Date(timeIntervalSince1970: 1),
            endDate: endDate
        )
        return packet
    }

    @Test("Start, response, finish in order ends with the final status and body")
    @MainActor
    func inOrderUpdates() {
        let device = AppTrafficDevice()
        _ = device.addPacket(newPacket: packet())
        _ = device.addPacket(newPacket: packet(statusCode: "200"))
        _ = device.addPacket(newPacket: packet(statusCode: "200", responseData: "e30=", endDate: Date(timeIntervalSince1970: 2)))

        let info = device.packets.first?.requestInfo
        #expect(device.packets.count == 1)
        #expect(info?.statusCode == "200")
        #expect(info?.responseData == "e30=")
        #expect(device.packets.first?.revision == 2)
    }

    @Test("A late start packet does not erase the status of a finished transaction")
    @MainActor
    func lateStartAfterFinish() {
        let device = AppTrafficDevice()
        _ = device.addPacket(newPacket: packet(statusCode: "200", responseData: "e30=", endDate: Date(timeIntervalSince1970: 2)))
        _ = device.addPacket(newPacket: packet())

        let info = device.packets.first?.requestInfo
        #expect(info?.statusCode == "200")
        #expect(info?.responseData == "e30=")
        #expect(info?.endDate != nil)
    }

    @Test("A late start packet does not erase the status from a response packet")
    @MainActor
    func lateStartAfterResponse() {
        let device = AppTrafficDevice()
        _ = device.addPacket(newPacket: packet(statusCode: "200"))
        _ = device.addPacket(newPacket: packet())

        let info = device.packets.first?.requestInfo
        #expect(info?.statusCode == "200")
        #expect(info?.responseHeaders?["Content-Type"] == "application/json")
    }

    @Test("Updating a packet notifies observers")
    @MainActor
    func updateNotifiesObservers() {
        let device = AppTrafficDevice()
        let original = packet()
        _ = device.addPacket(newPacket: original)
        var notifications = 0
        let token = original.objectWillChange.sink { notifications += 1 }
        _ = device.addPacket(newPacket: packet(statusCode: "200"))
        token.cancel()

        #expect(notifications == 1)
        #expect(original.requestInfo?.statusCode == "200")
    }

    @Test("Numeric status codes decode")
    func numericStatusDecodes() throws {
        let decoded = try decodePacket(#"{"packetId":"a","requestInfo":{"url":"https://x","statusCode":200}}"#)
        #expect(decoded.requestInfo?.statusCode == "200")
    }

    @Test("String status codes decode instead of dropping the packet")
    func stringStatusDecodes() throws {
        let decoded = try decodePacket(#"{"packetId":"a","requestInfo":{"url":"https://x","statusCode":"201"}}"#)
        #expect(decoded.requestInfo?.statusCode == "201")
    }
}
