//
//  TrafficRedactorTests.swift
//  AppTrafficInspectorTests
//

import Testing
@testable import App_Traffic_Inspector

struct TrafficRedactorTests {

    @Test("Header redaction in strict mode redacts Authorization")
    func headerRedactionStrict() {
        let headers = ["Authorization": "Bearer secret", "Content-Type": "application/json"]
        let result = TrafficRedactor.redact(headers: headers, mode: .strict)
        #expect(result["Authorization"] == "[REDACTED — MCP privacy mode]")
        #expect(result["Content-Type"] == "application/json")
    }

    @Test("Header redaction in moderate mode redacts Authorization")
    func headerRedactionModerate() {
        let headers = ["Authorization": "Bearer secret"]
        let result = TrafficRedactor.redact(headers: headers, mode: .moderate)
        #expect(result["Authorization"] == "[REDACTED — MCP privacy mode]")
    }

    @Test("Header redaction in off mode passes through")
    func headerRedactionOff() {
        let headers = ["Authorization": "Bearer secret"]
        let result = TrafficRedactor.redact(headers: headers, mode: .off)
        #expect(result["Authorization"] == "Bearer secret")
    }

    @Test("URL parameter redaction in strict mode")
    func urlRedactionStrict() {
        let url = "https://api.example.com?api_key=abc123&foo=bar"
        let result = TrafficRedactor.redactURL(urlString: url, mode: .strict)
        #expect(result?.contains("api_key=[REDACTED]") == true || result?.contains("api_key=%5BREDACTED%5D") == true)
    }

    @Test("Body pattern redaction redacts Bearer token")
    func bodyRedactionBearer() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xxx"
        let result = TrafficRedactor.redactBody(text: text, mode: .strict)
        #expect(result?.contains("Bearer [REDACTED]") == true)
    }

    @Test("JSON field redaction redacts password key")
    func jsonFieldRedaction() {
        let json = #"{"user":"alice","password":"secret123"}"#
        let data = json.data(using: .utf8)
        let result = TrafficRedactor.redactJSONFields(data: data, mode: .strict)
        let str = result.flatMap { String(data: $0, encoding: .utf8) }
        #expect(str?.contains("secret123") == false)
        #expect(str?.contains("[REDACTED]") == true)
    }
}
