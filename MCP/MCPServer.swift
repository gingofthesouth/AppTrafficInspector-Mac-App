//
//  MCPServer.swift
//  App Traffic Inspector
//
//  Streamable HTTP MCP server on 127.0.0.1:43436. POST /mcp for JSON-RPC.
//

import Foundation
import Network

let MCPPort: UInt16 = 43436
let MCPPath = "/mcp"

private actor SessionStore {
    var ids: Set<String> = []
    func add(_ id: String) { ids.insert(id) }
    func remove(_ id: String) { ids.remove(id) }
}

@MainActor
private final class SSESubscriberStore {
    static let shared = SSESubscriberStore()
    var subscribers: [(connection: NWConnection, disconnect: @Sendable () -> Void)] = []
    func add(_ connection: NWConnection, _ disconnect: @escaping @Sendable () -> Void) {
        subscribers.append((connection, disconnect))
    }
    func remove(_ connection: NWConnection) -> (@Sendable () -> Void)? {
        guard let index = subscribers.firstIndex(where: { $0.connection === connection }) else { return nil }
        let disconnect = subscribers[index].disconnect
        subscribers.remove(at: index)
        return disconnect
    }
    func removeAll() {
        subscribers.removeAll()
    }
    func getAll() -> [(connection: NWConnection, disconnect: @Sendable () -> Void)] {
        let copy = subscribers
        subscribers = []
        return copy
    }
}

final class MCPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let toolRegistry = MCPToolRegistry()
    private let sessionStore = SessionStore()

    init() {
        registerTools()
    }

    private func registerTools() {
        toolRegistry.register(ListProjectsTool())
        toolRegistry.register(ListDevicesTool())
        toolRegistry.register(ListPacketsTool())
        toolRegistry.register(GetPacketDetailTool())
        toolRegistry.register(SearchPacketsTool())
        toolRegistry.register(GetPacketCurlTool())
        toolRegistry.register(GetServerStatusTool())
        toolRegistry.register(ListConnectionsTool())
        toolRegistry.register(GetNetworkInterfacesTool())
        toolRegistry.register(GetErrorLogTool())
        toolRegistry.register(GetAppInfoTool())
        toolRegistry.register(GetRedactionSettingsTool())
        toolRegistry.register(SetRedactionModeTool())
        #if DEBUG
        toolRegistry.register(RestartListenerTool())
        toolRegistry.register(ClearPacketsTool())
        toolRegistry.register(InjectTestPacketTool())
        #endif
    }

    func start() {
        stop()
        do {
            let port = NWEndpoint.Port(rawValue: MCPPort)!
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    DevLogger.logInfo(message: "MCP server listening on 127.0.0.1:\(MCPPort)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .mcpServerDidStart, object: nil)
                    }
                case .failed(let err):
                    DevLogger.logError(message: "MCP listener failed: \(err.localizedDescription)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .mcpServerDidStop, object: nil)
                    }
                case .cancelled:
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .mcpServerDidStop, object: nil)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            DevLogger.logError(error)
        }
    }

    func stop() {
        Task { @MainActor in
            let toCancel = SSESubscriberStore.shared.getAll()
            for (conn, disconnect) in toCancel {
                disconnect()
                conn.cancel()
            }
        }
        listener?.cancel()
        listener = nil
    }

    private func logActivity(direction: MCPActivityDirection, summary: String, detail: String? = nil, statusCode: Int? = nil) {
        Task { @MainActor in
            MCPActivityLog.shared.log(direction: direction, summary: summary, detail: detail, statusCode: statusCode)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        if let endpoint = connection.currentPath?.remoteEndpoint {
            let desc = "\(endpoint)"
            logActivity(direction: .inbound, summary: "Connection from \(desc)")
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readRequest(connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func readRequest(_ connection: NWConnection) {
        var buffer = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if let error = error {
                    DevLogger.logError(error)
                    self.logActivity(direction: .internal_, summary: "Connection error", detail: error.localizedDescription, statusCode: 500)
                    self.sendResponse(connection, statusCode: 500, body: nil)
                    connection.cancel()
                    return
                }
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                }
                do {
                    var copy = buffer
                    let request = try MCPHTTPParser.parseRequest(&copy)
                    if let request = request {
                        buffer = copy
                        self.handleRequest(request, connection: connection)
                        if !buffer.isEmpty { readMore() }
                        else { readRequest(connection) }
                    } else {
                        if isComplete {
                            self.logActivity(direction: .internal_, summary: "MCP ReadMore Function Parse error: incomplete", statusCode: 400)
                            self.sendResponse(connection, statusCode: 400, body: nil)
                            connection.cancel()
                        } else {
                            readMore()
                        }
                    }
                } catch MCPHTTPParser.ParseError.incomplete {
                    readMore()
                } catch {
                    self.logActivity(direction: .internal_, summary: "Parse error", detail: String(describing: error), statusCode: 400)
                    self.sendResponse(connection, statusCode: 400, body: nil)
                    connection.cancel()
                }
            }
        }
        readMore()
    }

    private func handleRequest(_ request: MCPHTTPRequest, connection: NWConnection) {
        // Validate Origin per MCP spec (allow localhost)
        if let origin = request.headers["origin"], !origin.isEmpty,
           !origin.contains("127.0.0.1"), !origin.contains("localhost") {
            logActivity(direction: .internal_, summary: "Rejected: origin", detail: origin)
            sendResponse(connection, statusCode: 403, body: nil)
            return
        }

        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        if path != MCPPath {
            logActivity(direction: .internal_, summary: "404", detail: path)
            sendResponse(connection, statusCode: 404, body: nil)
            return
        }

        switch request.method {
        case "OPTIONS":
            logActivity(direction: .inbound, summary: "OPTIONS /mcp")
            sendResponse(connection, statusCode: 200, headers: ["Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, GET, DELETE"], body: nil)
        case "GET":
            logActivity(direction: .inbound, summary: "GET /mcp: SSE subscribe")
            handleSSE(connection: connection)
        case "DELETE":
            if let sid = request.headers["mcp-session-id"] {
                Task { await sessionStore.remove(sid) }
                logActivity(direction: .internal_, summary: "Session destroyed", detail: sid)
            }
            sendResponse(connection, statusCode: 200, body: nil)
        case "POST":
            guard let body = request.body, !body.isEmpty else {
                logActivity(direction: .internal_, summary: "POST /mcp: empty body", statusCode: 400)
                sendResponse(connection, statusCode: 400, body: nil)
                return
            }
            let methodName = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["method"] as? String ?? "?"
            logActivity(direction: .inbound, summary: "POST /mcp: \(methodName)")
            if methodName == "tools/call", let name = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["params"] as? [String: Any], let toolName = name["name"] as? String {
                logActivity(direction: .internal_, summary: "Executing tool: \(toolName)")
            }
            let sessionId = request.headers["mcp-session-id"]
            Task {
                let (responseDict, statusCode) = await MCPJSONRPCHandler.handle(body: body, sessionId: sessionId, toolRegistry: toolRegistry)
                Task { @MainActor in
                    MCPServerStatus.shared.totalRequestsHandled += 1
                    MCPServerStatus.shared.lastRequestTime = Date()
                }
                if let method = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["method"] as? String,
                   method == "initialize", responseDict?["result"] != nil {
                    let newSessionId = UUID().uuidString
                    await sessionStore.add(newSessionId)
                    Task { @MainActor in
                        MCPActivityLog.shared.log(direction: .internal_, summary: "Session created", detail: newSessionId)
                    }
                    let response = responseDict ?? [:]
                    let responseData = try? JSONSerialization.data(withJSONObject: response)
                    var headers: [String: String] = ["Content-Type": "application/json; charset=utf-8"]
                    headers["MCP-Session-Id"] = newSessionId
                    let responseBytes = MCPHTTPParser.response(statusCode: statusCode, headers: headers, body: responseData)
                    self.sendRaw(connection, data: responseBytes)
                    self.logActivity(direction: .outbound, summary: "Response", detail: "\(responseBytes.count) bytes", statusCode: statusCode)
                    return
                }
                let responseData = responseDict.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                let size = responseData?.count ?? 0
                self.logActivity(direction: .outbound, summary: "Response", detail: "\(size) bytes", statusCode: statusCode)
                self.sendResponse(connection, statusCode: statusCode, body: responseData)
            }
        default:
            logActivity(direction: .internal_, summary: "Method not allowed", detail: request.method, statusCode: 405)
            sendResponse(connection, statusCode: 405, body: nil)
        }
    }

    private func handleSSE(connection: NWConnection) {
        let headers = MCPHTTPParser.sseHeaders()
        sendRaw(connection, data: headers)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.removeSSE(connection)
            default:
                break
            }
        }

        Task { [weak self] in
            guard let self = self else { return }
            let (stream, disconnect) = await MainActor.run { TrafficEventBus.shared.subscribe() }

            await MainActor.run {
                SSESubscriberStore.shared.add(connection, disconnect)
                MCPServerStatus.shared.activeSSESubscribers = SSESubscriberStore.shared.subscribers.count
            }

            for await event in stream {
                let frame = MCPHTTPParser.sseFrame(jsonBody: event.toJSONRPCNotification())
                self.sendRaw(connection, data: frame)
            }
        }
    }

    private func removeSSE(_ connection: NWConnection) {
        Task { @MainActor in
            if let disconnect = SSESubscriberStore.shared.remove(connection) {
                disconnect()
            }
            MCPServerStatus.shared.activeSSESubscribers = SSESubscriberStore.shared.subscribers.count
        }
        connection.cancel()
    }

    private func sendResponse(_ connection: NWConnection, statusCode: Int, headers: [String: String]? = nil, body: Data?) {
        let defaultHeaders = ["Content-Type": "application/json; charset=utf-8"]
        let h = headers ?? defaultHeaders
        let data = MCPHTTPParser.response(statusCode: statusCode, headers: h, body: body)
        sendRaw(connection, data: data)
    }

    private func sendRaw(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
