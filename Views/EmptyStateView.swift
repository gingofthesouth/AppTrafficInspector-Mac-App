//
//  EmptyStateView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct EmptyStateView: View {
    @ObservedObject private var listenerStatus = TrafficListenerStatus.shared

    var body: some View {
        ContentUnavailableView {
            Label("Waiting for transactions", systemImage: "iphone")
                .symbolEffect(.pulse, options: .repeating)
        } description: {
            VStack(spacing: 10) {
                Text("Make sure your iOS device is on the same network and the app has AppTrafficKit enabled in Debug builds.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                HStack(spacing: 6) {
                    Circle()
                        .fill(listenerStatus.isReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(listenerStatus.summary)
                    Text("•")
                    Text(listenerStatus.detail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Quick start…") {
                NotificationCenter.default.post(name: .showQuickStartGuide, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
