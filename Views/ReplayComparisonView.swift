//
//  ReplayComparisonView.swift
//  App Traffic Inspector
//
//  Side-by-side comparison of a replayed transaction with the transaction it replayed.
//

import SwiftUI

struct HeaderDifference: Equatable, Identifiable {
    enum Change: String { case added, removed, changed, same }

    let name: String
    let original: String?
    let replay: String?

    var id: String { name.lowercased() }

    var change: Change {
        switch (original, replay) {
        case (nil, _?): .added
        case (_?, nil): .removed
        case let (a?, b?): a == b ? .same : .changed
        default: .same
        }
    }
}

struct ReplayComparison {
    let original: AppTrafficPacket?
    let replay: AppTrafficPacket

    private var originalInfo: AppTrafficRequestInfo? { original?.requestInfo }
    private var replayInfo: AppTrafficRequestInfo? { replay.requestInfo }

    /// Response header differences, matched case-insensitively, sorted by name. Unchanged headers are included.
    static func headerDifferences(original: [String: String]?, replay: [String: String]?) -> [HeaderDifference] {
        var byKey: [String: (name: String, original: String?, replay: String?)] = [:]
        for (key, value) in original ?? [:] {
            byKey[key.lowercased(), default: (key, nil, nil)].original = value
        }
        for (key, value) in replay ?? [:] {
            byKey[key.lowercased(), default: (key, nil, nil)].replay = value
        }
        return byKey.values
            .map { HeaderDifference(name: $0.name, original: $0.original, replay: $0.replay) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var headerDifferences: [HeaderDifference] {
        Self.headerDifferences(original: originalInfo?.responseHeaders, replay: replayInfo?.responseHeaders)
    }

    var bodiesIdentical: Bool {
        decoded(originalInfo?.responseData) == decoded(replayInfo?.responseData)
    }

    var summaryText: String {
        var lines = [
            "Status: \(Self.status(originalInfo)) → \(Self.status(replayInfo))",
            "Duration: \(Self.duration(originalInfo)) → \(Self.duration(replayInfo))",
            "Response size: \(PacketFormatting.byteSizeString(fromBase64: originalInfo?.responseData)) → \(PacketFormatting.byteSizeString(fromBase64: replayInfo?.responseData))",
            "Response body: \(bodiesIdentical ? "identical" : "different")",
        ]
        if let error = replay.replayError { lines.append("Replay error: \(error)") }
        let changed = headerDifferences.filter { $0.change != .same }
        if !changed.isEmpty {
            lines.append("Response header changes:")
            for diff in changed {
                lines.append("  [\(diff.change.rawValue)] \(diff.name): \(diff.original ?? "∅") → \(diff.replay ?? "∅")")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func status(_ info: AppTrafficRequestInfo?) -> String {
        guard let code = info?.statusCode, !code.isEmpty else { return "—" }
        return code
    }

    static func duration(_ info: AppTrafficRequestInfo?) -> String {
        guard let start = info?.startDate, let end = info?.endDate else { return "—" }
        return "\(Int(end.timeIntervalSince(start) * 1000)) ms"
    }

    private func decoded(_ base64: String?) -> Data {
        base64.flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) } ?? Data()
    }
}

struct ReplayComparisonView: View {
    let original: AppTrafficPacket?
    let replay: AppTrafficPacket
    @State private var showUnchangedHeaders = false

    private var comparison: ReplayComparison { ReplayComparison(original: original, replay: replay) }

    var body: some View {
        if original == nil {
            ContentUnavailableView(
                "Original Not Available",
                systemImage: "clock.arrow.circlepath",
                description: Text("The original transaction is no longer in history, so there is nothing to compare against.")
            )
            .accessibilityIdentifier("replay-original-missing")
        } else {
            VSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        metrics
                        headerDiff
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
                HSplitView {
                    bodyColumn(title: "Original response", info: original?.requestInfo)
                    bodyColumn(title: "Replay response", info: replay.requestInfo)
                }
                .frame(minHeight: 200)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("replay-compare")
        }
    }

    private var metrics: some View {
        let originalInfo = original?.requestInfo
        let replayInfo = replay.requestInfo
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text("Original").font(.caption).foregroundStyle(.secondary)
                Text("Replay").font(.caption).foregroundStyle(.secondary)
            }
            metricRow("Status", ReplayComparison.status(originalInfo), ReplayComparison.status(replayInfo))
            metricRow("Duration", ReplayComparison.duration(originalInfo), ReplayComparison.duration(replayInfo))
            metricRow(
                "Response size",
                PacketFormatting.byteSizeString(fromBase64: originalInfo?.responseData),
                PacketFormatting.byteSizeString(fromBase64: replayInfo?.responseData)
            )
            GridRow {
                Text("Response body").foregroundStyle(.secondary)
                Label(
                    comparison.bodiesIdentical ? "Identical" : "Different",
                    systemImage: comparison.bodiesIdentical ? "equal.circle" : "notequal.circle"
                )
                .foregroundStyle(comparison.bodiesIdentical ? .green : .orange)
                .gridCellColumns(2)
                .accessibilityIdentifier("replay-body-equality")
            }
        }
    }

    private func metricRow(_ label: String, _ original: String, _ replay: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(original).font(.system(.body, design: .monospaced))
            Text(replay)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(original == replay ? .primary : Color.orange)
        }
    }

    @ViewBuilder
    private var headerDiff: some View {
        let diffs = comparison.headerDifferences
        let visible = showUnchangedHeaders ? diffs : diffs.filter { $0.change != .same }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Response headers").font(.headline)
                Spacer()
                Toggle("Show unchanged", isOn: $showUnchangedHeaders)
                    .toggleStyle(.checkbox)
            }
            if visible.isEmpty {
                Text("No header changes").foregroundStyle(.secondary)
            }
            ForEach(visible) { diff in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(symbol(for: diff.change))
                        .foregroundStyle(color(for: diff.change))
                        .frame(width: 12)
                    Text(diff.name).fontWeight(.semibold)
                    switch diff.change {
                    case .added: Text(diff.replay ?? "")
                    case .removed: Text(diff.original ?? "").strikethrough()
                    case .changed: Text("\(diff.original ?? "") → \(diff.replay ?? "")")
                    case .same: Text(diff.replay ?? "").foregroundStyle(.secondary)
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }

    private func symbol(for change: HeaderDifference.Change) -> String {
        switch change {
        case .added: "+"
        case .removed: "−"
        case .changed: "~"
        case .same: "="
        }
    }

    private func color(for change: HeaderDifference.Change) -> Color {
        switch change {
        case .added: .green
        case .removed: .red
        case .changed: .orange
        case .same: .secondary
        }
    }

    private func bodyColumn(title: String, info: AppTrafficRequestInfo?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            BodyViewAsync(
                base64: info?.responseData,
                contentType: HTTPHeaders.value("Content-Type", in: info?.responseHeaders)
            )
        }
        .padding(4)
        .frame(minWidth: 200)
    }
}
