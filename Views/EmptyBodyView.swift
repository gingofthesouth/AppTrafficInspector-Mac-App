//
//  EmptyBodyView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct EmptyBodyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.and.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No body data")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
