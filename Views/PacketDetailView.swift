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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = packet?.requestInfo {
                // Header metrics (status, method, url, timing, sizes)
                header(info: info)
                    .padding(.bottom, 2)
                segmentedBar()

                contentView(for: info, tab: selected, packet: packet)

                HStack(spacing: 8) {
                    Spacer()
                    Button("Copy") { copyToClipboard(detailText(for: info, tab: selected, pretty: true)) }
                        .buttonStyle(.bordered)
                    if selected == .overview {
                        Button("cURL") { copyToClipboard(PacketFormatting.curlString(for: info)) }
                            .buttonStyle(.bordered)
                    }
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
            if let info = packet?.requestInfo,
               isMediaContentType(contentType(in: info.responseHeaders)) {
                selected = .responseBody
            } else {
                selected = .overview
            }
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
            return PacketFormatting.dataString(fromBase64: info.requestBody, pretty: true)
        case .responseHeaders:
            return keyValuesString(info.responseHeaders)
        case .responseBody:
            return PacketFormatting.dataString(fromBase64: info.responseData, pretty: true)
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
        let reqBody = PacketFormatting.dataString(fromBase64: info.requestBody, pretty: true)
        if !reqBody.isEmpty { s += "Request Body:\n" + reqBody + "\n\n" }
        let respBody = PacketFormatting.dataString(fromBase64: info.responseData, pretty: true)
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
            bodyView(base64: info.requestBody, contentType: contentType(in: info.requestHeaders))
        case .responseHeaders:
            ScrollView { textMono(keyValuesString(info.responseHeaders)) }
        case .responseBody:
            bodyView(base64: info.responseData, contentType: contentType(in: info.responseHeaders))
        }
    }

    @ViewBuilder
    private func bodyView(base64: String?, contentType: String?) -> some View {
        BodyViewAsync(base64: base64, contentType: contentType)
    }

    private func contentType(in headers: [String: String]?) -> String? {
        headers?.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
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
    var id: String { rawValue }
}
