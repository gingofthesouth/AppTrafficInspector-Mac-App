//
//  AppTrafficPublisher.swift
//  App Traffic Inspector
//

import Cocoa
import Network

@MainActor
final class TrafficListenerStatus: ObservableObject {
    static let shared = TrafficListenerStatus()

    @Published private(set) var summary = "Starting"
    @Published private(set) var detail = "Finding a network interface"
    @Published private(set) var isReady = false

    private init() {}

    func update(summary: String, detail: String, isReady: Bool) {
        self.summary = summary
        self.detail = detail
        self.isReady = isReady
    }
}

@MainActor
protocol AppTrafficPublisherDelegate: AnyObject {
    func didGetPacket(publisher: AppTrafficPublisher, packet: AppTrafficPacket)
}

final class AppTrafficPublisher: NSObject, @unchecked Sendable {

    var delegate: AppTrafficPublisherDelegate?
    
    private var listener: NWListener?
    /// Guarded by `connectionsLock`: mutated from the listener queue and every connection's queue.
    private var connections: [NWConnection] = []
    private let connectionsLock = NSLock()
    private var bonjourRegistrar: BonjourSingleInterfaceRegistrar?

    /// Current listener state for MCP get_server_status. Nil if listener not created.
    var listenerState: NWListener.State? { listener?.state }

    /// Active TCP connections for MCP list_connections.
    var activeConnections: [NWConnection] { connectionsLock.withLock { connections } }

    func startPublishing() {
        // Tear down existing listener and Bonjour so the port is released before rebinding
        let hadExisting = self.listener != nil
        bonjourRegistrar?.stop()
        bonjourRegistrar = nil
        if let listener = self.listener {
            listener.cancel()
            self.listener = nil
        }

        // Established device connections stay open and tracked across a listener restart;
        // they are removed when they fail or are cancelled.

        let start: @Sendable () -> Void = { [weak self] in self?.startPublishingImpl() }
        if hadExisting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: start)
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    func stopPublishing() {
        bonjourRegistrar?.stop()
        bonjourRegistrar = nil
        listener?.cancel()
        listener = nil
        let open = connectionsLock.withLock { () -> [NWConnection] in
            defer { connections.removeAll() }
            return connections
        }
        open.forEach { $0.cancel() }
        Task { @MainActor in
            TrafficListenerStatus.shared.update(
                summary: "Stopped",
                detail: "Traffic capture is not listening.",
                isReady: false
            )
        }
    }

    private func startPublishingImpl() {
        // Get the preferred network interface (ethernet > WiFi)
        guard let preferredInterface = NetworkInterfaceDetector.getPreferredInterface() else {
            print("No suitable network interface found")
            Task { @MainActor in
                TrafficListenerStatus.shared.update(
                    summary: "Waiting for network",
                    detail: "No active Ethernet or Wi-Fi interface was found.",
                    isReady: false
                )
            }
            self.restartAfterDelay()
            return
        }

        print("Using network interface: \(preferredInterface.name) (type: \(preferredInterface.type))")
        if !preferredInterface.ipv4Addresses.isEmpty {
            print("IPv4: \(preferredInterface.ipv4Addresses.joined(separator: ", "))")
        }
        if !preferredInterface.ipv6Addresses.isEmpty {
            print("IPv6: \(preferredInterface.ipv6Addresses.joined(separator: ", "))")
        }

        do {
            let port = NWEndpoint.Port(rawValue: AppTrafficConfiguration.netServicePort)!

            // Listen on all interfaces (0.0.0.0). requiredInterfaceType on NWListener can prevent
            // accepting connections to the advertised IP (connection refused). Bonjour is still
            // advertised only on the preferred interface via BonjourSingleInterfaceRegistrar.
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters, on: port)

            // Do not set listener.service — it advertises on all interfaces (e.g. bridge101).
            // We register Bonjour on the preferred interface only when the listener is ready.

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("Network listener ready on interface: \(preferredInterface.name)")
                    // Register Bonjour on this interface only so discovery returns only en0's IP
                    let registrar = BonjourSingleInterfaceRegistrar()
                    let domain = AppTrafficConfiguration.netServiceDomain
                    if registrar.start(
                        interfaceName: preferredInterface.name,
                        name: AppTrafficConfiguration.netServiceName,
                        type: AppTrafficConfiguration.netServiceType,
                        domain: domain,
                        port: AppTrafficConfiguration.netServicePort
                    ) {
                        self?.bonjourRegistrar = registrar
                    }
                    Task { @MainActor in
                        TrafficListenerStatus.shared.update(
                            summary: "Listening",
                            detail: "\(preferredInterface.name) • port \(AppTrafficConfiguration.portString)",
                            isReady: true
                        )
                    }
                case .failed(let error):
                    print("Network listener failed: \(error)")
                    Task { @MainActor in
                        TrafficListenerStatus.shared.update(
                            summary: "Capture unavailable",
                            detail: error.localizedDescription,
                            isReady: false
                        )
                    }
                    self?.restartAfterDelay()
                case .cancelled:
                    print("Network listener cancelled")
                    Task { @MainActor in
                        TrafficListenerStatus.shared.update(
                            summary: "Stopped",
                            detail: "Traffic capture is not listening.",
                            isReady: false
                        )
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.setupConnection(connection)
            }

            self.listener = listener

            listener.start(queue: DispatchQueue(label: "AppTrafficPublisher.listener"))

            // Bonjour is advertised only via NWListener.service (bound to preferred interface);
            // do not also publish NetService, which would register all interfaces and advertise wrong IPs (e.g. bridge101).

        } catch {
            print("Failed to start listener: \(error)")
            self.restartAfterDelay()
        }
    }

    private func setupConnection(_ connection: NWConnection) {
        print("New Connection from \(connection.endpoint)")
        connectionsLock.withLock { connections.append(connection) }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Connection ready")
                self?.readNextFrame(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.remove(connection)
            case .cancelled:
                print("Connection cancelled")
                self?.remove(connection)
            default:
                break
            }
        }
        
        // A serial queue per connection keeps its receive chain and parsing strictly ordered.
        connection.start(queue: DispatchQueue(label: "AppTrafficPublisher.connection", qos: .userInitiated))
    }
    
    /// Max JSON transaction size (bytes) to avoid corrupt length prefixes or unbounded allocations.
    private static let maxBodyLength = AppTrafficConfiguration.maximumTransactionBytes

    private func readNextFrame(on connection: NWConnection) {
        // Read 8-byte length prefix. Try big-endian first (wire contract), fall back to little-endian.
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] header, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("Failed to read header: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            guard let header = header, header.count == 8 else {
                let reason = header == nil ? "no data" : "got \(header?.count ?? 0) bytes (expected 8)"
                print("Failed to read header: \(reason)\(isComplete ? ", connection closed" : "")")
                connection.cancel()
                return
            }

            let raw = header.withUnsafeBytes { $0.load(as: UInt64.self) }
            let big = UInt64(bigEndian: raw)
            let little = UInt64(littleEndian: raw)
            let u64: UInt64
            if big <= Self.maxBodyLength {
                u64 = big
            } else if little <= Self.maxBodyLength {
                u64 = little
            } else {
                let ascii = String(decoding: header, as: UTF8.self)
                print("Failed to read body: length big=\(big) little=\(little) both exceed max \(Self.maxBodyLength); header bytes as text=\(ascii.debugDescription) (printable text means the stream is desynchronized after a short length prefix)")
                connection.cancel()
                return
            }
            let length = Int(truncatingIfNeeded: u64)
            guard length > 0 else {
                self.readNextFrame(on: connection)
                return
            }

            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] body, _, _, error in
                guard let self = self else { return }
                if let error = error {
                    print("Failed to read body: \(error.localizedDescription)")
                    connection.cancel()
                    return
                }
                guard let body = body, body.count == length else {
                    print("Failed to read body: got \(body?.count ?? 0) bytes (expected \(length))")
                    connection.cancel()
                    return
                }
                print("ready to parse body")
                self.parseBody(data: body)
                self.readNextFrame(on: connection)
            }
        }
    }
    
    private func remove(_ connection: NWConnection) {
        connectionsLock.withLock {
            connections.removeAll { $0 === connection }
        }
        // Do not restart when the last connection drops; only restart when the listener fails
    }
    
    private func restartAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startPublishing()
        }
    }
    
    func parseBody(data: Data) {
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .secondsSince1970
        
        do {
            
            let appTrafficPacket = try jsonDecoder.decode(AppTrafficPacket.self, from: data)
            
            DispatchQueue.main.async {
                self.delegate?.didGetPacket(publisher: self, packet: appTrafficPacket)
            }
            
        } catch {
            let tail = String(decoding: data.suffix(40), as: UTF8.self)
            let closed = data.last == UInt8(ascii: "}")
            print("Packet decode failed: declared/received \(data.count) bytes, ends with \(closed ? "'}'" : "non-'}' (frame likely truncated: sender length prefix shorter than payload)"), tail=\(tail.debugDescription), error=\(error)")
        }
    }
}
