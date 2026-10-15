//
//  QuickStartView.swift
//  App Traffic Inspector
//

import SwiftUI

enum QuickStartContent {
    /// Bump when onboarding copy or steps change so existing users see the sheet again.
    static let currentGuideVersion = 1

    /// Set when AppTrafficKit SPM or docs are public; until then the guide shows a short "coming soon" note.
    static let appTrafficKitDocumentationURL: URL? = nil
}

extension Notification.Name {
    static let showQuickStartGuide = Notification.Name("ShowQuickStartGuide")
}

struct QuickStartView: View {
    @Environment(\.dismiss) private var dismiss
    var onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("App Traffic Inspector listens on your Mac for HTTP traffic reported by iOS apps that include AppTrafficKit (Debug builds). No proxy or certificate setup is required.")
                        .font(.body)
                        .foregroundStyle(.primary)

                    Group {
                        step(1, "Connect your iPhone or simulator to the same Wi‑Fi network as this Mac.")
                        step(2, "Keep App Traffic Inspector running.")
                        step(3, "Add AppTrafficKit to your iOS app and enable it for Debug configurations.")
                        step(4, "Run the app and make network requests; projects, devices, and transactions appear in the sidebars.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discovery")
                            .font(.headline)
                        Text("Bonjour type \(AppTrafficConfiguration.netServiceType) on port \(AppTrafficConfiguration.portString) (service name is usually your Mac’s hostname: \(AppTrafficConfiguration.netServiceName)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    kitSection

                    VStack(alignment: .leading, spacing: 6) {
                        Text("MCP (AI tools)")
                            .font(.headline)
                        Text("To expose traffic to Cursor or other MCP clients, turn on Enable MCP Server in Settings and see the project README for connection details.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 24)
            .frame(minWidth: 520, idealWidth: 540, maxWidth: 560, minHeight: 380, idealHeight: 460)
            .navigationTitle("Quick Start")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SettingsLink {
                        Text("Open Settings")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onContinue()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var kitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AppTrafficKit")
                .font(.headline)
            if let url = QuickStartContent.appTrafficKitDocumentationURL {
                Link("Open documentation", destination: url)
                    .font(.callout)
            } else {
                Text("Distribution URL is not set yet. Follow the Usage section in the project README for updates when AppTrafficKit is published.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n).")
                .font(.body.weight(.semibold))
                .frame(minWidth: 22, alignment: .trailing)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}
