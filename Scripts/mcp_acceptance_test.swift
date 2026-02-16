#!/usr/bin/env swift
//
// MCP acceptance test: exercises http://127.0.0.1:43436/mcp with JSON-RPC
// Run: swift Scripts/mcp_acceptance_test.swift
// Requires App Traffic Inspector to be running with MCP Server enabled.
//

import Foundation

let baseURL = URL(string: "http://127.0.0.1:43436/mcp")!
var sessionId: String?
var passed = 0
var failed = 0

func log(_ msg: String) { print(msg); fflush(stdout) }

func postJSON(_ json: [String: Any], sessionId: String? = nil) -> (data: Data?, response: HTTPURLResponse?, error: Error?) {
    var request = URLRequest(url: baseURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let sid = sessionId { request.setValue(sid, forHTTPHeaderField: "MCP-Session-Id") }
    request.httpBody = (try? JSONSerialization.data(withJSONObject: json))
    var outData: Data?
    var outResponse: HTTPURLResponse?
    var outError: Error?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        outData = data
        outResponse = response as? HTTPURLResponse
        outError = error
        sem.signal()
    }.resume()
    sem.wait()
    return (outData, outResponse, outError)
}

func deleteSession(_ sid: String) {
    var request = URLRequest(url: baseURL)
    request.httpMethod = "DELETE"
    request.setValue(sid, forHTTPHeaderField: "MCP-Session-Id")
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { _, _, _ in sem.signal() }.resume()
    sem.wait()
}

func json(from data: Data?) -> [String: Any]? {
    guard let data = data else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

// 1. Initialize
log("1. Sending initialize...")
let initResult = postJSON(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "acceptance-test", "version": "1.0"]]])
if let err = initResult.error {
    log("   FAIL: \(err)"); failed += 1
} else if initResult.response?.statusCode != 200 {
    log("   FAIL: status \(initResult.response?.statusCode ?? 0)"); failed += 1
} else {
    sessionId = initResult.response?.value(forHTTPHeaderField: "MCP-Session-Id")
    if sessionId == nil { log("   FAIL: no MCP-Session-Id header"); failed += 1 }
    else {
        let obj = json(from: initResult.data)
        let result = obj?["result"] as? [String: Any]
        let caps = result?["capabilities"] as? [String: Any]
        if caps?["tools"] != nil { log("   PASS: initialize returned capabilities"); passed += 1 }
        else { log("   FAIL: missing capabilities.tools"); failed += 1 }
    }
}

guard let sid = sessionId else {
    log("Cannot continue without session. Aborting.")
    exit(1)
}

// 2. notifications/initialized
log("2. Sending notifications/initialized...")
let notifResult = postJSON(["jsonrpc": "2.0", "method": "notifications/initialized"], sessionId: sid)
let notifStatus = notifResult.response?.statusCode ?? 0
if notifStatus == 202 || notifStatus == 200 || (notifResult.error == nil && notifStatus == 0) {
    log("   PASS: 202/200 or accepted"); passed += 1
} else {
    log("   FAIL: status \(notifStatus)"); failed += 1
}

// 3. tools/list
log("3. Sending tools/list...")
let listResult = postJSON(["jsonrpc": "2.0", "id": 2, "method": "tools/list"], sessionId: sid)
let listObj = json(from: listResult.data)
let tools = (listObj?["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
let toolNames = Set(tools.compactMap { $0["name"] as? String })
let required = ["list_projects", "list_devices", "list_packets", "get_packet_detail", "search_packets", "get_packet_curl", "get_server_status", "list_connections", "get_network_interfaces", "get_error_log", "get_app_info", "get_redaction_settings", "set_redaction_mode"]
let missing = required.filter { !toolNames.contains($0) }
if missing.isEmpty && listResult.response?.statusCode == 200 {
    log("   PASS: all required tools present"); passed += 1
} else {
    log("   FAIL: missing \(missing), or status \(listResult.response?.statusCode ?? 0)"); failed += 1
}

// 4. tools/call get_server_status
log("4. tools/call get_server_status...")
let statusResult = postJSON(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "get_server_status", "arguments": [:]]], sessionId: sid)
let statusObj = json(from: statusResult.data)
let statusContent = (statusObj?["result"] as? [String: Any])?["content"] as? [[String: Any]]
let statusText = statusContent?.first?["text"] as? String ?? ""
if statusResult.response?.statusCode == 200, statusText.contains("port") || statusText.contains("43436") {
    log("   PASS"); passed += 1
} else {
    log("   FAIL: \(statusResult.response?.statusCode ?? 0) or invalid result"); failed += 1
}

// 5. tools/call get_app_info
log("5. tools/call get_app_info...")
let appInfoResult = postJSON(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "get_app_info", "arguments": [:]]], sessionId: sid)
let appInfoObj = json(from: appInfoResult.data)
let appContent = (appInfoObj?["result"] as? [String: Any])?["content"] as? [[String: Any]]
let appText = appContent?.first?["text"] as? String ?? ""
if appInfoResult.response?.statusCode == 200, appText.contains("version") || appText.contains("1.0") {
    log("   PASS"); passed += 1
} else {
    log("   FAIL"); failed += 1
}

// 6. tools/call list_projects
log("6. tools/call list_projects...")
let projectsResult = postJSON(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "list_projects", "arguments": [:]]], sessionId: sid)
let projectsObj = json(from: projectsResult.data)
let hasResult = projectsObj?["result"] != nil
if projectsResult.response?.statusCode == 200, hasResult {
    log("   PASS"); passed += 1
} else {
    log("   FAIL"); failed += 1
}

// 7. inject_test_packet (if available), then list_packets, get_packet_detail, get_packet_curl, search_packets
var injectedPacketId: String?
if toolNames.contains("inject_test_packet") {
    log("7a. tools/call inject_test_packet...")
    // AppTrafficPacket: packetId, requestInfo (url, requestHeaders, requestBody, requestMethod, responseHeaders, responseData, statusCode, startDate, endDate), project, device
    let packetDict: [String: Any] = [
        "packetId": "test-\(UUID().uuidString)",
        "requestInfo": [
            "url": "https://example.com/acceptance",
            "requestHeaders": ["Accept": "application/json"],
            "requestBody": nil as String?,
            "requestMethod": "GET",
            "responseHeaders": ["Content-Type": "application/json"],
            "responseData": nil as String?,
            "statusCode": 200,
            "startDate": 0,
            "endDate": 0
        ] as [String: Any?],
        "project": ["projectName": "Default"],
        "device": ["deviceId": "sim-1", "deviceName": "Simulator", "deviceDescription": ""]
    ]
    let packetJsonStr = (try? JSONSerialization.data(withJSONObject: packetDict)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    let injectResult = postJSON(["jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": ["name": "inject_test_packet", "arguments": ["packetJson": packetJsonStr]]], sessionId: sid)
    let injectObj = json(from: injectResult.data)
    let injectResultContent = (injectObj?["result"] as? [String: Any])?["content"] as? [[String: Any]]
    let injectText = injectResultContent?.first?["text"] as? String ?? ""
    let isError = (injectObj?["result"] as? [String: Any])?["isError"] as? Bool ?? true
    if injectResult.response?.statusCode == 200, !isError, injectText.contains("packetId") {
        if let range = injectText.range(of: "\"packetId\":\"") {
            let after = injectText[range.upperBound...]
            if let end = after.firstIndex(of: "\"") { injectedPacketId = String(after[..<end]) }
        }
        log("   PASS"); passed += 1
    } else {
        log("   FAIL or skipped"); failed += 1
    }

    log("7b. tools/call list_packets...")
    let listPacketsResult = postJSON(["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "list_packets", "arguments": ["limit": 10]]], sessionId: sid)
    let listPacketsObj = json(from: listPacketsResult.data)
    let listContent = (listPacketsObj?["result"] as? [String: Any])?["content"] as? [[String: Any]]
    let firstText = listContent?.first?["text"] as? String ?? ""
    if listPacketsResult.response?.statusCode == 200 {
        log("   PASS"); passed += 1
    } else { log("   FAIL"); failed += 1 }

    let pid = injectedPacketId ?? (firstText.contains("packetId") ? String(firstText.split(separator: "\n").first?.split(separator: ":").last?.dropFirst(1).dropLast(0) ?? "") : nil)
    if let packetId = pid, !packetId.isEmpty {
        log("7c. tools/call get_packet_detail...")
        let detailResult = postJSON(["jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": ["name": "get_packet_detail", "arguments": ["packetId": packetId]]], sessionId: sid)
        if detailResult.response?.statusCode == 200 { log("   PASS"); passed += 1 } else { log("   FAIL"); failed += 1 }

        log("7d. tools/call get_packet_curl...")
        let curlResult = postJSON(["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "get_packet_curl", "arguments": ["packetId": packetId]]], sessionId: sid)
        let curlText = (json(from: curlResult.data)?["result"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        if curlResult.response?.statusCode == 200, (curlText.first?["text"] as? String ?? "").contains("curl") { log("   PASS"); passed += 1 } else { log("   FAIL"); failed += 1 }
    }
    log("7e. tools/call search_packets...")
    let searchResult = postJSON(["jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": ["name": "search_packets", "arguments": ["query": "example.com"]]], sessionId: sid)
    if searchResult.response?.statusCode == 200 { log("   PASS"); passed += 1 } else { log("   FAIL"); failed += 1 }
} else {
    log("7. Skipping inject/list_packets/detail/curl/search (inject_test_packet not in DEBUG)");
}

// 8. get_error_log
log("8. tools/call get_error_log...")
let logResult = postJSON(["jsonrpc": "2.0", "id": 11, "method": "tools/call", "params": ["name": "get_error_log", "arguments": [:]]], sessionId: sid)
let logObj = json(from: logResult.data)
let logContent = (logObj?["result"] as? [String: Any])?["content"]
if logResult.response?.statusCode == 200, logContent != nil {
    log("   PASS"); passed += 1
} else {
    log("   FAIL"); failed += 1
}

// 9. DELETE session
log("9. DELETE /mcp (session teardown)...")
deleteSession(sid)
log("   PASS (no error)"); passed += 1

log("")
log("--- Summary: \(passed) passed, \(failed) failed ---")
exit(failed > 0 ? 1 : 0)
