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
    case document
}

struct MediaPayload: Hashable, Identifiable, Sendable {
    let data: Data
    let mimeType: String
    let kind: MediaKind
    var filename: String?

    var id: Int {
        var hasher = Hasher()
        hasher.combine(mimeType)
        hasher.combine(data)
        return hasher.finalize()
    }

    var suggestedFilename: String {
        if let filename, !filename.isEmpty { return BinaryFormatting.sanitizedFilename(filename) }
        return "body." + (BinaryFormatting.fileExtension(forMimeType: mimeType) ?? "bin")
    }
}

enum BodyDisplayResult {
    case loading
    case json(String, embeddedMedia: [EmbeddedMedia])
    case plain(String)
    case media(MediaPayload)
    case multipart([MultipartPart])
    case form([FormField])
    case binary(Data)
    case oversized(Int)
    case invalidMedia(String)
    case empty
    
    func bodyDisplayResultToOverviewString() -> String {
        switch self {
        case .loading, .empty: return ""
        case .json(let s, let embedded):
            guard !embedded.isEmpty else { return s }
            let notes = embedded.map { "  \($0.path): \($0.payload.kind.rawValue) (\($0.payload.mimeType), \($0.payload.data.count) bytes)" }
            return s + "\n\nEmbedded media:\n" + notes.joined(separator: "\n")
        case .plain(let s): return s
        case .media(let payload): return "\(payload.kind.rawValue.capitalized) (\(payload.mimeType), \(payload.data.count) bytes)"
        case .multipart(let parts): return MultipartSummary.text(for: parts)
        case .form(let fields): return fields.map { "\($0.name)=\($0.value)" }.joined(separator: "\n")
        case .binary(let data): return "(binary data \(data.count) bytes)"
        case .oversized(let count): return "(media exceeds 25 MiB limit, \(count) encoded bytes)"
        case .invalidMedia(let message): return "(invalid media: \(message))"
        }
    }
}

enum MultipartSummary {
    static func text(for parts: [MultipartPart]) -> String {
        parts.map { part in
            let name = part.name ?? "(unnamed)"
            if let value = part.textValue {
                return "\(name) = \(value)"
            }
            var details = ["\(part.body.count) bytes"]
            if let type = part.contentType { details.insert(type, at: 0) }
            if let filename = part.filename { details.insert("filename=\(filename)", at: 0) }
            return "\(name) = [file: \(details.joined(separator: ", "))]"
        }.joined(separator: "\n")
    }
}
