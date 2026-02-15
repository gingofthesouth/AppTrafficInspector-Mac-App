//
//  JSONHighlighter.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

/// Max characters to run regex highlighting on; rest is left plain to avoid 100% CPU on large payloads.
private let maxHighlightLength = 200_000

enum JSONHighlighter {
    static func highlight(text: String) -> NSAttributedString {
        let work = text.count > maxHighlightLength
            ? String(text.prefix(maxHighlightLength)) + "\n\n… (truncated for display)"
            : text
        let attributed = NSMutableAttributedString(string: work)
        let fullRange = NSRange(location: 0, length: (work as NSString).length)

        let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        attributed.addAttributes([
            .font: mono,
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        // Very lightweight regex-based syntax highlighting (on truncated string to avoid CPU spike)
        // keys: "key":
        apply(regex: #"\"([^"\\]|\\.)*\"\s*(?=:)"#, in: work, to: attributed, color: NSColor.systemBlue)
        // string values: : "value"
        apply(regex: #"(?<=:)\s*\"([^"\\]|\\.)*\""#, in: work, to: attributed, color: NSColor.systemGreen)
        // numbers
        apply(regex: #"(?<=:)\s*-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?"#, in: work, to: attributed, color: NSColor.systemOrange)
        // booleans/null
        apply(regex: #"(?<=:)\s*(true|false|null)"#, in: work, to: attributed, color: NSColor.systemPurple)
        // punctuation
        apply(regex: #"[\{\}\[\],:]"#, in: work, to: attributed, color: NSColor.secondaryLabelColor)

        return attributed
    }

    private static func apply(regex pattern: String, in text: String, to attr: NSMutableAttributedString, color: NSColor) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            attr.addAttribute(.foregroundColor, value: color, range: m.range)
        }
    }
}
