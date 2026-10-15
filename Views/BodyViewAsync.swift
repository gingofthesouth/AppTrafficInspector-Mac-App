//
//  BodyViewAsync.swift
//  
//
//  Created by Ernest Cunningham on 16/02/2026.
//

import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

struct BodyViewAsync: View {
    let base64: String?
    var contentType: String?
    @State private var result: BodyDisplayResult = .loading

    var body: some View {
        bodyContent
            .task(id: base64) {
                result = .loading
                guard base64 != nil else {
                    result = .empty
                    return
                }
                let resolved = await Task.detached(priority: .userInitiated) {
                    base64?.convertBase64ToPrettyJson(contentType: contentType) ?? .empty
                }.value
                result = resolved
            }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch result {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .json(let string):
            JSONTextView(text: string)
        case .plain(let string):
            ScrollView {
                Text(string)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        case .media(let payload):
            MediaPreviewView(payload: payload)
        case .binary(let count):
            ScrollView {
                Text("(binary data \(count) bytes)")
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        case .oversized(let count):
            ContentUnavailableView(
                "Media Too Large",
                systemImage: "exclamationmark.triangle",
                description: Text("\(count) encoded bytes exceeds the 25 MiB preview limit.")
            )
        case .invalidMedia(let message):
            ContentUnavailableView(
                "Media Could Not Be Displayed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .empty:
            EmptyBodyView()
        }
    }
}

extension String {
    func convertBase64ToPrettyJson(
        contentType: String? = nil,
        maxMediaBytes: Int = AppTrafficConfiguration.maximumTransactionBytes
    ) -> BodyDisplayResult {
        guard utf8.count <= ((maxMediaBytes + 2) / 3) * 4 + 4 else {
            return .oversized(utf8.count)
        }
        guard let data = Data(base64Encoded: self, options: .ignoreUnknownCharacters) else {
            return .empty
        }
        guard data.count <= maxMediaBytes else {
            return .oversized(utf8.count)
        }

        if let media = MediaPayload.classify(data: data, contentType: contentType) {
            return .media(media)
        }
        
        if let obj = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let json = String(data: pretty, encoding: .utf8) {
            return .json(json.replacingOccurrences(of: "\\/", with: "/"))
        }
        
        if let str = String(data: data, encoding: .utf8) {
            return .plain(str)
        }
        
        return .binary(data.count)
    }
}

private extension MediaPayload {
    static func classify(data: Data, contentType: String?) -> MediaPayload? {
        let normalized = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalized {
            if normalized.hasPrefix("image/") {
                return MediaPayload(data: data, mimeType: normalized, kind: .image)
            }
            if normalized.hasPrefix("video/") {
                return MediaPayload(data: data, mimeType: normalized, kind: .video)
            }
            if normalized.hasPrefix("audio/") {
                return MediaPayload(data: data, mimeType: normalized, kind: .audio)
            }
        }

        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return MediaPayload(data: data, mimeType: "image/png", kind: .image)
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return MediaPayload(data: data, mimeType: "image/jpeg", kind: .image)
        }
        if bytes.starts(with: Array("GIF8".utf8)) {
            return MediaPayload(data: data, mimeType: "image/gif", kind: .image)
        }
        if bytes.count >= 12, String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp" {
            return MediaPayload(data: data, mimeType: "video/mp4", kind: .video)
        }
        return nil
    }
}

private struct MediaPreviewView: View {
    let payload: MediaPayload
    @State private var player: AVPlayer?
    @State private var temporaryURL: URL?
    @State private var errorMessage: String?
    @State private var imageScale = 1.0

    var body: some View {
        Group {
            switch payload.kind {
            case .image:
                imagePreview
            case .video:
                playerPreview(systemImage: "film")
            case .audio:
                playerPreview(systemImage: "waveform")
            }
        }
        .task(id: payload.id) {
            preparePlayerIfNeeded()
        }
        .onDisappear {
            cleanup()
        }
        .accessibilityIdentifier("media-preview-\(payload.kind.rawValue)")
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = NSImage(data: payload.data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 240, minHeight: 180)
                    .scaleEffect(imageScale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                imageScale = min(max(value.magnification, 0.5), 6)
                            }
                    )
                    .padding()
            }
            .overlay(alignment: .topTrailing) {
                HStack {
                    Button("Actual Size", systemImage: "1.magnifyingglass") {
                        imageScale = 1
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    Button("Save…", systemImage: "square.and.arrow.down") {
                        savePayload()
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("save-media-button")
                }
                .padding(8)
            }
        } else {
            mediaError("The image data is corrupt or unsupported.")
        }
    }

    @ViewBuilder
    private func playerPreview(systemImage: String) -> some View {
        if let errorMessage {
            mediaError(errorMessage)
        } else if let player {
            VStack(spacing: 12) {
                if payload.kind == .video {
                    VideoPlayer(player: player)
                        .frame(minHeight: 260)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                    VideoPlayer(player: player)
                        .frame(height: 72)
                }
                HStack {
                    Text("\(payload.mimeType) • \(ByteCountFormatter.string(fromByteCount: Int64(payload.data.count), countStyle: .file))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save…", systemImage: "square.and.arrow.down") {
                        savePayload()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("save-media-button")
                }
            }
            .padding()
        } else {
            ProgressView("Preparing media…")
        }
    }

    private func mediaError(_ message: String) -> some View {
        ContentUnavailableView(
            "Media Could Not Be Displayed",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    private func preparePlayerIfNeeded() {
        guard payload.kind != .image else { return }
        cleanup()
        do {
            let fileExtension = UTType(mimeType: payload.mimeType)?.preferredFilenameExtension ?? "media"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppTrafficInspector-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try payload.data.write(to: url, options: .atomic)
            temporaryURL = url
            player = AVPlayer(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePayload() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "response.\(UTType(mimeType: payload.mimeType)?.preferredFilenameExtension ?? "bin")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try payload.data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cleanup() {
        player?.pause()
        player = nil
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
            self.temporaryURL = nil
        }
    }
}
