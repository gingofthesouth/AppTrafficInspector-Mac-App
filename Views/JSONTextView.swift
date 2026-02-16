//
//  JSONTextView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct JSONTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        scroll.documentView = textView

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = text
        // Show plain text immediately so the view isn't blank while highlighting
        textView.string = currentText
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor

        Task.detached(priority: .userInitiated) {
            let attributed = JSONHighlighter.highlight(text: currentText)
            await MainActor.run {
                // Only apply if this view is still showing the same text (avoids overwriting after tab/packet change)
                guard textView.string == currentText else { return }
                textView.textStorage?.setAttributedString(attributed)
            }
        }
    }
}
