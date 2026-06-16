//
//  AppTrafficPublisher.swift
//  App Traffic Inspector
//

import Cocoa
import Network

@MainActor
protocol AppTrafficPublisherDelegate: AnyObject {
    func didGetPacket(publisher: AppTrafficPublisher, packet: AppTrafficPacket)
}

final class AppTrafficPublisher: NSObject, @unchecked Sendable {

    var delegate: AppTrafficPublisherDelegate?
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var bonjourRegistrar: BonjourSingleInterfaceRegistrar?

    /// Current listener state for MCP get_server_status. Nil if listener not created.
    var listenerState: NWListener.State? { listener?.state }

    /// Active TCP connections for MCP list_connections.
    var activeConnections: [NWConnection] { connections }

    func startPublishing() {
        // Tear down existing listener and Bonjour so the port is released before rebinding
        let hadExisting = self.listener != nil
        bonjourRegistrar?.stop()
        bonjourRegistrar = nil
        if let listener = self.listener {
            listener.cancel()
            self.listener = nil
        }
        self.connections = []

        let start: @Sendable () -> Void = { [weak self] in self?.startPublishingImpl() }
        if hadExisting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: start)
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    private func startPublishingImpl() {
        // Get the preferred network interface (ethernet > WiFi)
        guard let preferredInterface = NetworkInterfaceDetector.getPreferredInterface() else {
            print("No suitable network interface found")
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
                case .failed(let error):
                    print("Network listener failed: \(error)")
                    self?.restartAfterDelay()
                case .cancelled:
                    print("Network listener cancelled")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.setupConnection(connection)
            }

            self.listener = listener

            listener.start(queue: .global(qos: .background))

            // Bonjour is advertised only via NWListener.service (bound to preferred interface);
            // do not also publish NetService, which would register all interfaces and advertise wrong IPs (e.g. bridge101).

        } catch {
            print("Failed to start listener: \(error)")
            self.restartAfterDelay()
        }
    }

    private func setupConnection(_ connection: NWConnection) {
        print("New Connection")
        connections.append(connection)
        
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
        
        connection.start(queue: .global(qos: .background))
    }
    
    /// Max JSON body size (bytes) to avoid corrupt length prefix or framework issues.
    private static let maxBodyLength = 2 * 1024 * 1024

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
                print("Failed to read body: length big=\(big) little=\(little) both exceed max \(Self.maxBodyLength)")
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
        if let index = connections.firstIndex(where: { $0 === connection }) {
            connections.remove(at: index)
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
            print(error)
        }
    }
}
