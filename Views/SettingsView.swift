//
//  SettingsView.swift
//  App Traffic Inspector
//

import SwiftUI

private let mcpServerEnabledKey = "mcpServerEnabled"

struct SettingsView: View {
    @AppStorage(mcpServerEnabledKey) private var mcpServerEnabled = false
    @AppStorage(TrafficRedactor.redactionModeKey) private var redactionModeRaw = RedactionMode.strict.rawValue
    @ObservedObject private var mcpStatus = MCPServerStatus.shared
    @ObservedObject private var listenerStatus = TrafficListenerStatus.shared


    var body: some View {
        Form {
            Section("Traffic Capture") {
                LabeledContent("Status") {
                    Label(
                        listenerStatus.summary,
                        systemImage: listenerStatus.isReady
                            ? "antenna.radiowaves.left.and.right"
                            : "exclamationmark.triangle"
                    )
                    .foregroundStyle(listenerStatus.isReady ? .green : .orange)
                }
                LabeledContent("Connection", value: listenerStatus.detail)
                LabeledContent("Transaction limit", value: "1,000 per device")
                LabeledContent("Media budget", value: "250 MiB per device")
            }
            Section("MCP Server") {
                Toggle("Enable MCP Server", isOn: $mcpServerEnabled)
                    .onChange(of: mcpServerEnabled) { _, newValue in
                        NotificationCenter.default.post(
                            name: newValue ? .mcpServerStart : .mcpServerStop,
                            object: nil
                        )
                    }
                Text("Port: \(String(MCPPort))")
                    .foregroundStyle(.secondary)
                Text("URL: http://127.0.0.1:\(String(MCPPort))\(MCPPath)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                if mcpStatus.isMCPServerRunning {
                    Label("Running", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Stopped", systemImage: "circle")
                        .foregroundStyle(.secondary)
                }
                Text("SSE subscribers: \(mcpStatus.activeSSESubscribers)")
                    .foregroundStyle(.secondary)
                Text("Requests: \(mcpStatus.totalRequestsHandled)")
                    .foregroundStyle(.secondary)
                if let last = mcpStatus.lastRequestTime {
                    Text("Last request: \(last, style: .relative) ago")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Picker("Redaction mode", selection: $redactionModeRaw) {
                    Text("Strict").tag(RedactionMode.strict.rawValue)
                    Text("Moderate").tag(RedactionMode.moderate.rawValue)
                    Text("Off").tag(RedactionMode.off.rawValue)
                }
                .onChange(of: redactionModeRaw) { _, newValue in
                    TrafficRedactor.setMode(RedactionMode(rawValue: newValue) ?? .strict)
                }
                if redactionModeRaw == RedactionMode.off.rawValue {
                    Text("Sensitive data will be exposed to MCP clients.")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 390)
    }
}

extension Notification.Name {
    static let mcpServerStart = Notification.Name("MCPServerStart")
    static let mcpServerStop = Notification.Name("MCPServerStop")
    static let mcpServerDidStart = Notification.Name("MCPServerDidStart")
    static let mcpServerDidStop = Notification.Name("MCPServerDidStop")
}
