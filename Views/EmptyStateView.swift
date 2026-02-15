//
//  EmptyStateView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct EmptyStateView: View {
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 16) {
                Image(systemName: "iphone")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text("Waiting for incoming connections")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Make sure your iOS device is on the same network and the app has AppTrafficKit enabled in Debug builds.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 420)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }
}
