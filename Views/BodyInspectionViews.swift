//
//  BodyInspectionViews.swift
//  App Traffic Inspector
//
//  Structured renderers for multipart uploads, URL-encoded forms, JSON with embedded
//  base64 media, and opaque binary bodies.
//

import SwiftUI
import AppKit

enum DataSaver {
    @MainActor
    static func save(_ data: Data, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

struct MultipartPartsView: View {
    let parts: [MultipartPart]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("multipart • \(parts.count) part\(parts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(parts) { part in
                    MultipartPartRow(part: part)
                }
            }
            .padding(.trailing, 4)
        }
        .accessibilityIdentifier("multipart-parts")
    }
}

private struct MultipartPartRow: View {
    let part: MultipartPart

    private var media: MediaPayload? {
        guard part.textValue == nil else { return nil }
        return MediaPayload.classify(data: part.body, contentType: part.contentType, filename: part.filename)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let value = part.textValue {
                    Text(value.isEmpty ? "(empty)" : value)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let media {
                    MediaPreviewView(payload: media)
                        .frame(minHeight: media.kind == .audio ? 160 : 240, maxHeight: 420)
                } else {
                    BinaryDataView(data: part.body, suggestedFilename: suggestedFilename, compact: true)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: part.textValue == nil ? "paperclip" : "character.cursor.ibeam")
                    .foregroundStyle(.secondary)
                Text(part.name ?? "(unnamed)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                if let filename = part.filename {
                    Text(filename).foregroundStyle(.secondary)
                }
                if let type = part.contentType {
                    Text(type).font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(part.body.count), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if part.textValue == nil {
                    Button("Save Part…", systemImage: "square.and.arrow.down") {
                        DataSaver.save(part.body, suggestedFilename: suggestedFilename)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
        }
        .accessibilityIdentifier("multipart-part-\(part.name ?? String(part.index))")
    }

    private var suggestedFilename: String {
        if let filename = part.filename, !filename.isEmpty { return BinaryFormatting.sanitizedFilename(filename) }
        let ext = BinaryFormatting.fileExtension(forMimeType: part.contentType) ?? "bin"
        return BinaryFormatting.sanitizedFilename(part.name ?? "part-\(part.index)") + "." + ext
    }
}

struct FormFieldsView: View {
    let fields: [FormField]

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    GridRow {
                        Text(field.name)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                        Text(field.value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.trailing, 4)
        }
        .accessibilityIdentifier("form-fields")
    }
}

struct EmbeddedMediaJSONView: View {
    let json: String
    let embedded: [EmbeddedMedia]
    @State private var showMedia = true

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 4) {
                DisclosureGroup(isExpanded: $showMedia) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(embedded) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(item.path) • \(item.payload.mimeType)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    MediaPreviewView(payload: item.payload)
                                        .frame(minHeight: 200, maxHeight: 320)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Embedded media (\(embedded.count))", systemImage: "photo.on.rectangle")
                }
            }
            .frame(minHeight: 40)
            JSONTextView(text: json)
                .frame(minHeight: 120)
        }
        .accessibilityIdentifier("embedded-media")
    }
}

struct BinaryDataView: View {
    let data: Data
    let suggestedFilename: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Binary data • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save…", systemImage: "square.and.arrow.down") {
                    DataSaver.save(data, suggestedFilename: suggestedFilename)
                }
                .buttonStyle(.bordered)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(BinaryFormatting.hexDump(data, limit: compact ? 128 : 1024))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: compact ? 120 : .infinity)
        }
        .accessibilityIdentifier("binary-body")
    }
}
