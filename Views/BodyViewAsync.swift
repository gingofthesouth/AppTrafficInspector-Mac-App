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
import PDFKit

struct BodyViewAsync: View {
    let base64: String?
    var contentType: String?
    /// Declared `Content-Length`, used to flag bodies the capture library missed or truncated.
    var declaredLength: Int?
    var role: BodyRole = .response
    /// Original byte count when the producer reported that it truncated this body.
    var producerTruncatedFrom: Int?
    @State private var result: BodyDisplayResult = .loading
    @State private var capturedByteCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice = captureNotice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("body-capture-notice")
            }
            bodyContent
        }
        .task(id: base64) {
            result = .loading
            capturedByteCount = 0
            guard let base64 else {
                result = .empty
                return
            }
            let contentType = contentType
            let resolved = await Task.detached(priority: .userInitiated) {
                (base64.convertBase64ToPrettyJson(contentType: contentType), base64.decodedBase64ByteCount)
            }.value
            result = resolved.0
            capturedByteCount = resolved.1
        }
    }

    private var captureNotice: String? {
        if case .loading = result { return nil }
        if let original = producerTruncatedFrom {
            let counts = original > 0 ? "captured \(capturedByteCount) of \(original) bytes" : "captured \(capturedByteCount) bytes"
            return "The capture library truncated this body (\(counts)). "
                + "Raise maxBodyBytes in the app's AppTrafficInspectorKit configuration to capture it fully."
        }
        guard let declaredLength, declaredLength > 0, capturedByteCount < declaredLength else { return nil }
        if capturedByteCount == 0 {
            return "No \(role.rawValue) body was captured, but Content-Length is \(declaredLength) bytes. "
                + "The capture library may not have seen this body."
        }
        return "Captured \(capturedByteCount) of \(declaredLength) bytes (Content-Length). "
            + "The body was probably truncated during capture, so media may not render."
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch result {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .json(let string, let embedded):
            if embedded.isEmpty {
                JSONTextView(text: string)
            } else {
                EmbeddedMediaJSONView(json: string, embedded: embedded)
            }
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
        case .multipart(let parts):
            MultipartPartsView(parts: parts)
        case .form(let fields):
            FormFieldsView(fields: fields)
        case .binary(let data):
            BinaryDataView(data: data, suggestedFilename: "\(role.rawValue)-body.bin")
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

enum BodyRole: String {
    case request
    case response
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
        return BodyInspector.inspect(data, contentType: contentType)
    }

    var decodedBase64ByteCount: Int {
        Data(base64Encoded: self, options: .ignoreUnknownCharacters)?.count ?? 0
    }
}

enum BodyInspector {
    static func inspect(_ data: Data, contentType: String?) -> BodyDisplayResult {
        guard !data.isEmpty else { return .empty }
        let mime = HTTPHeaders.mimeType(contentType)

        if let boundary = MultipartParser.boundary(fromContentType: contentType),
           let parts = MultipartParser.parse(data, boundary: boundary) {
            return .multipart(parts)
        }
        if mime == "application/x-www-form-urlencoded", let fields = FormURLEncodedParser.parse(data) {
            return .form(fields)
        }
        if let media = MediaPayload.classify(data: data, contentType: contentType) {
            return .media(media)
        }
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers, .fragmentsAllowed]),
           obj is [Any] || obj is [String: Any],
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let json = String(data: pretty, encoding: .utf8) {
            return .json(json.replacingOccurrences(of: "\\/", with: "/"), embeddedMedia: EmbeddedMediaFinder.find(in: obj))
        }
        if let str = String(data: data, encoding: .utf8) {
            return .plain(str)
        }
        return .binary(data)
    }
}

struct MediaPreviewView: View {
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
            case .document:
                documentPreview
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
    private var documentPreview: some View {
        if let document = PDFDocument(data: payload.data) {
            PDFKitView(document: document)
                .overlay(alignment: .topTrailing) {
                    Button("Save…", systemImage: "square.and.arrow.down") { savePayload() }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("save-media-button")
                        .padding(8)
                }
        } else {
            mediaError("The PDF data is corrupt or unsupported.")
        }
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
        guard payload.kind == .video || payload.kind == .audio else { return }
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
        panel.nameFieldStringValue = payload.suggestedFilename
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

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
