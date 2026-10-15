//
//  MCPConsoleView.swift
//  App Traffic Inspector
//
//  Live log of MCP server activity (requests, responses, errors).
//

import SwiftUI

struct MCPConsoleView: View {
    @State private var log = MCPActivityLog.shared
    @State private var filterInbound = true
    @State private var filterOutbound = true
    @State private var filterInternal = true
    @State private var searchText = ""
    @State private var expandedIds: Set<UUID> = []

    private var filteredEntries: [MCPActivityLog.Entry] {
        let list = log.entries
        let byDirection = list.filter { entry in
            switch entry.direction {
            case .inbound: return filterInbound
            case .outbound: return filterOutbound
            case .internal_: return filterInternal
            }
        }
        if searchText.isEmpty { return byDirection }
        let q = searchText.lowercased()
        return byDirection.filter {
            $0.summary.lowercased().contains(q) || ($0.detail?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            filterBar
            Divider()
            listContent
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private var toolbar: some View {
        HStack {
            Button("Clear") {
                Task { @MainActor in MCPActivityLog.shared.clear() }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("k", modifiers: .command)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Toggle("In", isOn: $filterInbound)
                .toggleStyle(.button)
            Toggle("Out", isOn: $filterOutbound)
                .toggleStyle(.button)
            Toggle("Internal", isOn: $filterInternal)
                .toggleStyle(.button)
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var listContent: some View {
        List(filteredEntries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    directionIcon(entry.direction)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary)
                            .font(.system(.body, design: .monospaced))
                        if let code = entry.statusCode {
                            Text("\(code)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if entry.detail != nil {
                        if expandedIds.contains(entry.id) { expandedIds.remove(entry.id) }
                        else { expandedIds.insert(entry.id) }
                    }
                }
                if let detail = entry.detail, expandedIds.contains(entry.id) {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    private func directionIcon(_ direction: MCPActivityDirection) -> some View {
        Group {
            switch direction {
            case .inbound:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            case .outbound:
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
            case .internal_:
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(.body)
    }
}
