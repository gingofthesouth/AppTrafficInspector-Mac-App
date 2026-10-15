//
//  PacketDetailView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct PacketDetailView: View {
    let packet: AppTrafficPacket?
    @State private var selected: DetailTab = .overview
    @State private var isReplaying = false
    @State private var confirmingReplay = false
    @State private var copiedNotice: String?

    /// Unsafe-method replays are confirmed once per app launch.
    @MainActor private static var unsafeReplayConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = packet?.requestInfo {
                // Header metrics (status, method, url, timing, sizes)
                header(info: info)
                    .padding(.bottom, 2)
                if let packet, packet.isReplay {
                    replayBanner(packet)
                }
                segmentedBar()

                contentView(for: info, tab: selected, packet: packet)

                HStack(spacing: 8) {
                    if let copiedNotice {
                        Text(copiedNotice)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("copied-notice")
                    }
                    Spacer()
                    Button("Copy") { copyToClipboard(detailText(for: info, tab: selected, pretty: true)) }
                        .buttonStyle(.bordered)
                    Button("cURL") { copyCurl(for: info) }
                        .buttonStyle(.bordered)
                        .help("Copy a cURL command. Binary bodies are written to the export folder set in Settings.")
                        .accessibilityIdentifier("copy-curl-button")
                    Button {
                        requestReplay()
                    } label: {
                        if isReplaying {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Replay", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isReplaying || info.url == nil)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Resend this request from this Mac (⌘R)")
                    .accessibilityIdentifier("replay-button")
                }
                .confirmationDialog(
                    "Replay \(info.requestMethod?.rawValue ?? "") request?",
                    isPresented: $confirmingReplay
                ) {
                    Button("Replay") {
                        if replaySource?.requestInfo?.requestMethod?.isUnsafe == true {
                            Self.unsafeReplayConfirmed = true
                        }
                        performReplay()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(replayConfirmationMessage)
                }
            } else {
                ContentUnavailableView(
                    "No Transaction Selected",
                    systemImage: "network",
                    description: Text("Select a transaction to inspect its request and response.")
                )
            }
        }
        .padding(12)
        .task(id: packet?.packetId) {
            copiedNotice = nil
            selected = initialTab(for: packet)
        }
    }

    private func initialTab(for packet: AppTrafficPacket?) -> DetailTab {
        guard let packet, let info = packet.requestInfo else { return .overview }
        if packet.isReplay { return .compare }
        if isMediaContentType(contentType(in: info.responseHeaders)) { return .responseBody }
        let requestType = contentType(in: info.requestHeaders)
        if isMediaContentType(requestType) || HTTPHeaders.mimeType(requestType) == "multipart/form-data" {
            return .requestBody
        }
        return .overview
    }

    // MARK: - Replay

    /// Replaying a replay re-sends the original request.
    private var replaySource: AppTrafficPacket? {
        guard let packet else { return nil }
        return packet.replayOfPacketId.flatMap { AppTrafficController.shared.packet(withId: $0) } ?? packet
    }

    private var replayNeedsUnsafeConfirmation: Bool {
        replaySource?.requestInfo?.requestMethod?.isUnsafe == true && !Self.unsafeReplayConfirmed
    }

    private var replayBodyTruncated: Bool {
        replaySource?.requestInfo?.requestBodyTruncated == true
    }

    private var replayConfirmationMessage: String {
        var lines: [String] = []
        if replayBodyTruncated {
            lines.append("The captured request body was truncated by AppTrafficInspectorKit, so the replay sends an incomplete body.")
        }
        if replayNeedsUnsafeConfirmation {
            lines.append("This method can change data on the server. The request is sent again from this Mac with the captured headers, including cookies and authorization. You won't be asked about the method again until the app restarts.")
        }
        return lines.joined(separator: "\n\n")
    }

    private func requestReplay() {
        if replayNeedsUnsafeConfirmation || replayBodyTruncated {
            confirmingReplay = true
        } else {
            performReplay()
        }
    }

    private func performReplay() {
        guard let source = replaySource, !isReplaying else { return }
        isReplaying = true
        Task {
            await ReplayService.shared.replay(source)
            isReplaying = false
        }
    }

    @ViewBuilder
    private func replayBanner(_ packet: AppTrafficPacket) -> some View {
        HStack(spacing: 8) {
            Label("Replay", systemImage: "arrow.clockwise.circle.fill")
                .foregroundStyle(.tint)
            if let error = packet.replayError {
                Text("Failed: \(error)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("replay-error")
            }
            Spacer()
            if let originalId = packet.replayOfPacketId,
               let original = AppTrafficController.shared.packet(withId: originalId) {
                Button("Show Original") { AppTrafficController.shared.reveal(original) }
                    .buttonStyle(.link)
            } else {
                Text("Original no longer in history").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .accessibilityIdentifier("replay-banner")
    }

    // MARK: - cURL

    private func copyCurl(for info: AppTrafficRequestInfo) {
        let transactionId = packet?.packetId ?? UUID().uuidString
        var exported: [URL] = []
        let curl = PacketFormatting.curlString(for: info) { data, filename in
            let url = try BodyExportStore.shared.write(data, filename: filename, transactionId: transactionId)
            exported.append(url)
            return url
        }
        copyToClipboard(curl)
        if let first = exported.first {
            let folder = first.deletingLastPathComponent().path
            copiedNotice = "cURL copied • \(exported.count) body file\(exported.count == 1 ? "" : "s") in \(folder)"
        } else {
            copiedNotice = "cURL copied"
        }
    }
    
    // MARK: - Segmented bar
    private func segmentedBar() -> some View {
        Picker("Detail Section", selection: $selected) {
            Label("Overview", systemImage: "doc.text.magnifyingglass")
                .tag(DetailTab.overview)
            Label("Req Headers", systemImage: "square.and.arrow.up.on.square")
                .tag(DetailTab.requestHeaders)
            Label("Parameters", systemImage: "slider.horizontal.3")
                .tag(DetailTab.parameters)
            Label("Req Body", systemImage: "tray.and.arrow.up")
                .tag(DetailTab.requestBody)
            Label("Resp Headers", systemImage: "arrow.down.doc")
                .tag(DetailTab.responseHeaders)
            Label("Resp Body", systemImage: "tray.and.arrow.down")
                .tag(DetailTab.responseBody)
            if packet?.isReplay == true {
                Label("Compare", systemImage: "arrow.left.arrow.right")
                    .tag(DetailTab.compare)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.vertical, 2)
    }

    private func detailText(for info: AppTrafficRequestInfo, tab: DetailTab, pretty: Bool) -> String {
        switch tab {
        case .overview:
            return overviewString(info)
        case .requestHeaders:
            return keyValuesString(info.requestHeaders)
        case .parameters:
            if let urlStr = info.url, let url = URL(string: urlStr) {
                return queryItemsString(url: url)
            }
            return ""
        case .requestBody:
            return PacketFormatting.bodyText(fromBase64: info.requestBody, contentType: contentType(in: info.requestHeaders))
        case .responseHeaders:
            return keyValuesString(info.responseHeaders)
        case .responseBody:
            return PacketFormatting.bodyText(fromBase64: info.responseData, contentType: contentType(in: info.responseHeaders))
        case .compare:
            guard let packet else { return "" }
            let original = packet.replayOfPacketId.flatMap { AppTrafficController.shared.packet(withId: $0) }
            return ReplayComparison(original: original, replay: packet).summaryText
        }
    }

    private func overviewString(_ info: AppTrafficRequestInfo) -> String {
        var s = ""
        s += (info.requestMethod?.rawValue ?? "") + " " + (info.url ?? "") + "\n\n"
        if let code = info.statusCode { s += "Response Code: \(code)\n\n" }
        if let urlStr = info.url, let url = URL(string: urlStr) {
            let params = queryItemsString(url: url)
            if !params.isEmpty { s += "URL Parameters:\n" + params + "\n\n" }
        }
        let reqHeaders = keyValuesString(info.requestHeaders)
        if !reqHeaders.isEmpty { s += "Request Headers:\n" + reqHeaders + "\n\n" }
        let reqBody = PacketFormatting.bodyText(fromBase64: info.requestBody, contentType: contentType(in: info.requestHeaders))
        if !reqBody.isEmpty { s += "Request Body:\n" + reqBody + "\n\n" }
        let respBody = PacketFormatting.bodyText(fromBase64: info.responseData, contentType: contentType(in: info.responseHeaders))
        if !respBody.isEmpty { s += "Response Body:\n" + respBody }
        return s
    }

    private func keyValuesString(_ dict: [String:String]?) -> String {
        guard let dict = dict, !dict.isEmpty else { return "" }
        return dict.keys.sorted().map { key in
            "\(key): \(dict[key] ?? "")"
        }.joined(separator: "\n")
    }

    private func queryItemsString(url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, !items.isEmpty else { return "" }
        return items.map { "\($0.name): \($0.value ?? "")" }.joined(separator: "\n")
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Header helpers
    private func header(info: AppTrafficRequestInfo) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let code = info.statusCode, !code.isEmpty {
                Text(code)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor(code: code))
            }
            if let method = info.requestMethod {
                Text(method.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(method.color().opacity(0.15))
                    .foregroundStyle(method.color())
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text(info.url ?? "")
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            if let start = info.startDate, let end = info.endDate {
                let durationMs = Int(end.timeIntervalSince(start) * 1000)
                Text("\(durationMs) ms").foregroundStyle(.secondary)
            }
            Text("Req: \(PacketFormatting.byteSizeString(fromBase64: info.requestBody))")
                .foregroundStyle(.tertiary)
            Text("Resp: \(PacketFormatting.byteSizeString(fromBase64: info.responseData))")
                .foregroundStyle(.tertiary)
        }
    }

    private func statusColor(code: String) -> Color {
        if let value = Int(code) {
            if value >= 200 && value < 300 { return Color(nsColor: .systemGreen) }
            if value >= 300 && value < 400 { return Color(nsColor: .systemOrange) }
            if value >= 400 { return Color(nsColor: .systemRed) }
        }
        return .primary
    }

}

// MARK: - Content Rendering
extension PacketDetailView {
    @ViewBuilder
    fileprivate func contentView(for info: AppTrafficRequestInfo, tab: DetailTab, packet: AppTrafficPacket?) -> some View {
        switch tab {
        case .overview:
            OverviewContentAsync(info: info, packet: packet)
        case .requestHeaders:
            ScrollView { textMono(keyValuesString(info.requestHeaders)) }
        case .parameters:
            if let urlStr = info.url, let url = URL(string: urlStr) {
                ScrollView { textMono(queryItemsString(url: url)) }
            } else { EmptyBodyView() }
        case .requestBody:
            bodyView(
                base64: info.requestBody,
                headers: info.requestHeaders,
                role: .request,
                truncatedFrom: info.requestBodyTruncated == true ? (info.requestBodyOriginalByteCount ?? 0) : nil
            )
        case .responseHeaders:
            ScrollView { textMono(keyValuesString(info.responseHeaders)) }
        case .responseBody:
            bodyView(
                base64: info.responseData,
                headers: info.responseHeaders,
                role: .response,
                truncatedFrom: info.responseDataTruncated == true ? (info.responseDataOriginalByteCount ?? 0) : nil
            )
        case .compare:
            if let packet {
                ReplayComparisonView(
                    original: packet.replayOfPacketId.flatMap { AppTrafficController.shared.packet(withId: $0) },
                    replay: packet
                )
            }
        }
    }

    @ViewBuilder
    private func bodyView(base64: String?, headers: [String: String]?, role: BodyRole, truncatedFrom: Int?) -> some View {
        BodyViewAsync(
            base64: base64,
            contentType: contentType(in: headers),
            declaredLength: HTTPHeaders.value("Content-Length", in: headers).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            role: role,
            producerTruncatedFrom: truncatedFrom
        )
    }

    private func contentType(in headers: [String: String]?) -> String? {
        HTTPHeaders.value("Content-Type", in: headers)
    }

    private func isMediaContentType(_ contentType: String?) -> Bool {
        guard let contentType = contentType?.lowercased() else { return false }
        return contentType.hasPrefix("image/")
            || contentType.hasPrefix("video/")
            || contentType.hasPrefix("audio/")
    }

    private func textMono(_ text: String) -> some View {
        Text(text)
            .textSelection(.enabled)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case requestHeaders = "Headers"
    case parameters = "Parameters"
    case requestBody = "Body"
    case responseHeaders = "Resp Headers"
    case responseBody = "Resp Body"
    case compare = "Compare"
    var id: String { rawValue }
}
