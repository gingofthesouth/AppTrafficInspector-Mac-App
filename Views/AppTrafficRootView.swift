import SwiftUI
import AppKit

struct AppTrafficRootView: View {
    @ObservedObject var store: AppTrafficStore
    @AppStorage("hasSeenQuickStart") private var hasSeenQuickStart = false
    @AppStorage("quickStartGuideVersion") private var savedQuickStartGuideVersion = 0
    @State private var showQuickStart = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var shouldShowQuickStartOnLaunch: Bool {
        #if DEBUG
        if UITestConfiguration.isUITesting { return false }
        #endif
        return !hasSeenQuickStart || savedQuickStartGuideVersion < QuickStartContent.currentGuideVersion
    }

    private var isFilterActive: Bool {
        let status = store.statusFilterTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return !store.addressFilterTerm.isEmpty || !store.methodFilterTerm.isEmpty || !status.isEmpty
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            projectsColumn
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
        } content: {
            devicesColumn
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 330)
        } detail: {
            if store.projects.isEmpty || store.devices.isEmpty || (store.packets.isEmpty && !isFilterActive) {
                EmptyStateView()
            } else {
                transactionsAndDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                CaptureStatusPill()
            }
        }
        .onAppear {
            columnVisibility = .all
            if shouldShowQuickStartOnLaunch {
                showQuickStart = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickStartGuide)) { _ in
            showQuickStart = true
        }
        .sheet(isPresented: $showQuickStart) {
            QuickStartView {
                hasSeenQuickStart = true
                savedQuickStartGuideVersion = QuickStartContent.currentGuideVersion
            }
        }
    }

    private var projectsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader("Projects", count: store.projects.count, systemImage: "square.stack.3d.up")
                .padding(.top, 8)
            List(store.projects, id: \.self) { project in
                HStack {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                    Text(project.projectName ?? "Unnamed")
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .accessibilityIdentifier("project-row-\(project.projectName ?? "unnamed")")
                .onTapGesture { store.select(project: project) }
                .listRowBackground(
                    project === store.selectedProject
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
            }
            .accessibilityIdentifier("projects-list")
            .listStyle(.sidebar)
        }
    }

    private var devicesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader("Devices", count: store.devices.count, systemImage: "iphone")
                .padding(.top, 8)
            List(store.devices, id: \.self) { device in
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.deviceName ?? "Device")
                        .fontWeight(.medium)
                    if let description = device.deviceDescription, !description.isEmpty {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .accessibilityIdentifier("device-row-\(device.deviceId ?? "unknown")")
                .onTapGesture { store.select(device: device) }
                .listRowBackground(
                    device === store.selectedDevice
                        ? Color.accentColor.opacity(0.18)
                        : Color.clear
                )
            }
            .accessibilityIdentifier("devices-list")
            .listStyle(.sidebar)
        }
    }

    private var transactionsAndDetail: some View {
        VSplitView {
            VStack(spacing: 0) {
                transactionsHeader
                Divider()
                if store.packets.isEmpty && isFilterActive {
                    FilterEmptyView(clearAction: clearAllFilters)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    transactionsList
                }
            }
            .frame(minHeight: 180)

            PacketDetailView(packet: store.selectedPacket, revision: store.selectedPacket?.revision ?? 0)
                .frame(minHeight: 200)
        }
    }

    private var transactionsHeader: some View {
        HStack(spacing: 8) {
            Label("\(store.packets.count) Transactions", systemImage: "network")
                .font(.headline)
            TextField("Filter address", text: $store.addressFilterTerm)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("transaction-address-filter")
            TextField("Status", text: $store.statusFilterTerm)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 75)
            TextField("Method", text: $store.methodFilterTerm)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 85)
            Button("Clear Transactions", systemImage: "trash") {
                store.clearPackets()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("clear-transactions-button")
            if isFilterActive {
                Button("Clear Filters", action: clearAllFilters)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var transactionsList: some View {
        List(store.packets, id: \.self) { transaction in
            Button {
                store.select(packet: transaction)
            } label: {
                TransactionRow(transaction: transaction)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("transaction-row-\(transaction.packetId ?? "unknown")")
            .listRowBackground(
                store.selectedPacket === transaction
                    ? Color.accentColor.opacity(0.14)
                    : Color.clear
            )
        }
        .accessibilityIdentifier("transactions-list")
        .listStyle(.plain)
    }

    private func columnHeader(_ title: String, count: Int, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
    }

    private func clearAllFilters() {
        store.addressFilterTerm = ""
        store.methodFilterTerm = ""
        store.statusFilterTerm = ""
    }
}

/// Observes its packet so in-place updates (e.g. the status code arriving after the request
/// started) redraw the row; List diffing alone treats the same packet instance as unchanged.
private struct TransactionRow: View {
    @ObservedObject var transaction: AppTrafficPacket

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mediaSystemImage(for: transaction))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(transaction.requestInfo?.statusCode ?? "")
                .foregroundStyle(statusColor(for: transaction))
                .frame(width: 42, alignment: .leading)
            MethodBadge(method: transaction.requestInfo?.requestMethod)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if transaction.isReplay {
                        Text("Replay")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(transaction.replayError == nil ? Color.accentColor : .red)
                            .accessibilityIdentifier("replay-badge")
                    }
                    Text(transaction.requestInfo?.url ?? "")
                        .lineLimit(1)
                }
                if let contentType = contentType(for: transaction) {
                    Text(contentType)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(transaction.requestInfo?.startDate?.readable ?? "")
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func statusColor(for transaction: AppTrafficPacket) -> Color {
        guard let codeString = transaction.requestInfo?.statusCode,
              let code = Int(codeString)
        else {
            return .primary
        }
        if (200..<300).contains(code) { return .green }
        if (300..<400).contains(code) { return .orange }
        if code >= 400 { return .red }
        return .primary
    }

    private func contentType(for transaction: AppTrafficPacket) -> String? {
        transaction.requestInfo?.responseHeaders?
            .first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?
            .value
    }

    private func mediaSystemImage(for transaction: AppTrafficPacket) -> String {
        let type = contentType(for: transaction)?.lowercased() ?? ""
        if type.hasPrefix("image/") { return "photo" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        let requestType = transaction.requestInfo?.requestHeaders?
            .first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?
            .value.lowercased() ?? ""
        if requestType.hasPrefix("multipart/") || requestType.hasPrefix("image/")
            || requestType.hasPrefix("video/") || requestType.hasPrefix("audio/") {
            return "paperclip"
        }
        return "doc.text"
    }
}
