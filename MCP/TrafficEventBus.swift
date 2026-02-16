//
//  TrafficEventBus.swift
//  App Traffic Inspector
//
//  Domain events from packet ingestion, broadcast to SSE subscribers.
//

import Foundation

enum TrafficEvent: Sendable {
    case projectAdded(projectName: String)
    case deviceAdded(projectName: String, deviceId: String, deviceName: String)
    case packetAdded(projectName: String, deviceId: String, packetId: String, method: String, url: String, statusCode: String)
    case packetUpdated(projectName: String, deviceId: String, packetId: String, method: String, url: String, statusCode: String)

    func toJSONRPCNotification() -> [String: Any] {
        switch self {
        case .projectAdded(let projectName):
            return [
                "jsonrpc": "2.0",
                "method": "notifications/traffic/projectAdded",
                "params": ["projectName": projectName] as [String: Any]
            ] as [String: Any]
        case .deviceAdded(let projectName, let deviceId, let deviceName):
            return [
                "jsonrpc": "2.0",
                "method": "notifications/traffic/deviceAdded",
                "params": [
                    "projectName": projectName,
                    "deviceId": deviceId,
                    "deviceName": deviceName
                ] as [String: Any]
            ] as [String: Any]
        case .packetAdded(let projectName, let deviceId, let packetId, let method, let url, let statusCode):
            return [
                "jsonrpc": "2.0",
                "method": "notifications/traffic/packetAdded",
                "params": [
                    "projectName": projectName,
                    "deviceId": deviceId,
                    "packetId": packetId,
                    "method": method,
                    "url": url,
                    "statusCode": statusCode
                ] as [String: Any]
            ] as [String: Any]
        case .packetUpdated(let projectName, let deviceId, let packetId, let method, let url, let statusCode):
            return [
                "jsonrpc": "2.0",
                "method": "notifications/traffic/packetUpdated",
                "params": [
                    "projectName": projectName,
                    "deviceId": deviceId,
                    "packetId": packetId,
                    "method": method,
                    "url": url,
                    "statusCode": statusCode
                ] as [String: Any]
            ] as [String: Any]
        }
    }
}

@MainActor
final class TrafficEventBus {
    static let shared = TrafficEventBus()

    private var subscribers: [UUID: AsyncStream<TrafficEvent>.Continuation] = [:]

    private init() {}

    func emit(_ event: TrafficEvent) {
        for (_, continuation) in subscribers {
            continuation.yield(event)
        }
    }

    /// Returns a new stream and a disconnect closure. Call the disconnect closure when the subscriber goes away (e.g. SSE connection closed).
    func subscribe() -> (stream: AsyncStream<TrafficEvent>, disconnect: @Sendable () -> Void) {
        let id = UUID()
        var continuation: AsyncStream<TrafficEvent>.Continuation!
        let stream = AsyncStream<TrafficEvent> { continuation = $0 }
        subscribers[id] = continuation
        let disconnect: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.disconnect(id: id)
            }
        }
        return (stream, disconnect)
    }

    private func disconnect(id: UUID) {
        subscribers[id]?.finish()
        subscribers.removeValue(forKey: id)
    }
}
