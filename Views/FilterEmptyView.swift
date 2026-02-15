//
//  FilterEmptyView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct FilterEmptyView: View {
    var clearAction: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No packets match the current filters")
                .foregroundStyle(.secondary)
            Button("Clear filters", action: clearAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
