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
        ContentUnavailableView {
            Label("No Matching Transactions", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No transactions match the current filters.")
        } actions: {
            Button("Clear filters", action: clearAction)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
