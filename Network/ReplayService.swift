//
//  ReplayService.swift
//  App Traffic Inspector
//
//  Re-sends a captured request from the Mac and records the result as a new transaction
//  linked to the original via `replayOfPacketId`.
//

import Foundation

enum ReplayRequestBuilder {
    /// Headers URLSession manages itself or that would be wrong when re-sent from another host.
    static let strippedHeaders: Set<String> = [
        "host", "content-length", "connection", "keep-alive", "proxy-connection",
        "transfer-encoding", "te", "trailer", "upgrade", "expect",
    ]

    enum BuildError: LocalizedError {
        case missingURL
        case unsupportedURL(String)

        var errorDescription: String? {
            switch self {
            case .missingURL: "The transaction has no URL to replay."
            case .unsupportedURL(let url): "Only http and https URLs can be replayed (\(url))."
            }
        }
    }

    static func makeRequest(from info: AppTrafficRequestInfo, timeout: TimeInterval = 60) throws -> URLRequest {
        guard let urlString = info.url, !urlString.isEmpty else { throw BuildError.missingURL }
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw BuildError.unsupportedURL(urlString)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = (info.requestMethod ?? .get).rawValue
        // Send exactly the captured Cookie header, not cookies from the Mac's own jar.
        request.httpShouldHandleCookies = false
        for (key, value) in info.requestHeaders ?? [:] where !strippedHeaders.contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let b64 = info.requestBody,
           let body = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
           !body.isEmpty {
            request.httpBody = body
        }
        return request
    }
}

/// Blocks redirects so the replay shows exactly what the server answered to this request.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

@MainActor
final class ReplayService {
    static let shared = ReplayService()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    /// Replays `original`, ingests the result into the controller, and returns the new packet.
    @discardableResult
    func replay(_ original: AppTrafficPacket, controller: AppTrafficController = .shared) async -> AppTrafficPacket {
        let packet = AppTrafficPacket()
        packet.packetId = "replay-\(UUID().uuidString)"
        packet.project = original.project
        packet.device = original.device
        packet.replayOfPacketId = original.packetId

        let source = original.requestInfo ?? AppTrafficRequestInfo()
        var info = AppTrafficRequestInfo(
            url: source.url,
            requestHeaders: source.requestHeaders,
            requestBody: source.requestBody,
            requestMethod: source.requestMethod
        )
        let start = Date()
        info.startDate = start

        do {
            let request = try ReplayRequestBuilder.makeRequest(from: source)
            let (data, response) = try await session.data(for: request)
            info.endDate = Date()
            if let http = response as? HTTPURLResponse {
                info.statusCode = String(http.statusCode)
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    headers[String(describing: key)] = String(describing: value)
                }
                info.responseHeaders = headers
            }
            info.responseData = data.isEmpty ? nil : data.base64EncodedString()
        } catch {
            info.endDate = Date()
            packet.replayError = error.localizedDescription
        }

        packet.requestInfo = info
        controller.ingest(packet)
        controller.reveal(packet)
        return packet
    }
}
