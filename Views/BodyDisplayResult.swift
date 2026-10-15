//
//  BodyDisplayResult.swift
//  
//
//  Created by Ernest Cunningham on 16/02/2026.
//

import SwiftUI
import AppKit

enum MediaKind: String, Sendable {
    case image
    case video
    case audio
}

struct MediaPayload: Hashable, Identifiable, Sendable {
    let data: Data
    let mimeType: String
    let kind: MediaKind

    var id: Int {
        var hasher = Hasher()
        hasher.combine(mimeType)
        hasher.combine(data)
        return hasher.finalize()
    }
}

enum BodyDisplayResult {
    case loading
    case json(String)
    case plain(String)
    case media(MediaPayload)
    case binary(Int)
    case oversized(Int)
    case invalidMedia(String)
    case empty
    
    func bodyDisplayResultToOverviewString() -> String {
        switch self {
        case .loading, .empty: return ""
        case .json(let s), .plain(let s): return s
        case .media(let payload): return "\(payload.kind.rawValue.capitalized) (\(payload.mimeType), \(payload.data.count) bytes)"
        case .binary(let count): return "(binary data \(count) bytes)"
        case .oversized(let count): return "(media exceeds 25 MiB limit, \(count) encoded bytes)"
        case .invalidMedia(let message): return "(invalid media: \(message))"
        }
    }
}
