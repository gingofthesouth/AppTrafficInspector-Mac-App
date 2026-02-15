//
//  AppTrafficRootView.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI
import AppKit

struct AppTrafficRootView: View {
    @ObservedObject var store: AppTrafficStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private var isFilterActive: Bool {
        let status = store.statusFilterTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        return !store.addressFilterTerm.isEmpty || !store.methodFilterTerm.isEmpty || !status.isEmpty
    }

    private func clearAllFilters() {
        store.addressFilterTerm = ""
        store.methodFilterTerm = ""
        store.statusFilterTerm = ""
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            projectsColumn
                .navigationTitle("Projects")
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            devicesColumn
                .navigationTitle("Devices")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if store.projects.isEmpty || store.devices.isEmpty || (store.packets.isEmpty && !isFilterActive) {
                EmptyStateView()
            } else {
                packetsAndDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { columnVisibility = .all }
    }

    private var projectsColumn: some View {
        List(store.projects, id: \.self) { project in
            HStack {
                Text(project.projectName ?? "Unnamed")
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(project: project) }
            .listRowBackground(project === store.selectedProject ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }

    private var devicesColumn: some View {
        List(store.devices, id: \.self) { device in
            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName ?? "Device")
                if let desc = device.deviceDescription, !desc.isEmpty {
                    Text(desc).foregroundStyle(.secondary).font(.footnote)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(device: device) }
            .listRowBackground(device === store.selectedDevice ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }

    private var packetsAndDetail: some View {
        VSplitView {
            VStack(spacing: 8) {
                packetsHeader(clearFilters: clearAllFilters, isFilterActive: isFilterActive)
                if store.packets.isEmpty && isFilterActive {
                    FilterEmptyView(clearAction: clearAllFilters)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    packetsList
                }
            }
            .padding(8)
            PacketDetailView(packet: store.selectedPacket)
                .padding(8)
        }
        .background(.thinMaterial)
    }

    private func packetsHeader(clearFilters: @escaping () -> Void, isFilterActive: Bool) -> some View {
        HStack(spacing: 8) {
            TextField("Filter address", text: $store.addressFilterTerm)
                .textFieldStyle(.roundedBorder)
            TextField("Status", text: $store.statusFilterTerm)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
            TextField("Method", text: $store.methodFilterTerm)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
            Spacer()
            Button {
                store.clearPackets()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            if isFilterActive {
                Button("Clear filters", action: clearFilters)
            }
        }
    }

    private var packetsList: some View {
        List(store.packets, id: \.self) { packet in
            HStack(spacing: 12) {
                Text(packet.requestInfo?.statusCode ?? "")
                    .foregroundStyle(statusColor(for: packet))
                    .frame(width: 50, alignment: .leading)
                Text(packet.requestInfo?.requestMethod?.rawValue ?? "")
                    .foregroundStyle(methodColor(for: packet))
                    .frame(width: 55, alignment: .leading)
                Text(packet.requestInfo?.url ?? "")
                    .lineLimit(1)
                Spacer()
                Text(packet.requestInfo?.startDate?.readable ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(packet: packet) }
            .listRowBackground((store.selectedPacket === packet) ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func statusColor(for packet: AppTrafficPacket) -> Color {
        guard let codeStr = packet.requestInfo?.statusCode, let code = Int(codeStr) else { return .primary }
        if code >= 200 && code < 300 { return Color(nsColor: .systemGreen) }
        if code >= 300 && code < 400 { return Color(nsColor: .systemOrange) }
        if code >= 400 { return Color(nsColor: .systemRed) }
        return .primary
    }

    private func methodColor(for packet: AppTrafficPacket) -> Color {
        switch packet.requestInfo?.requestMethod {
        case .get?: return Color(nsColor: .systemTeal)
        case .put?: return Color(nsColor: .systemBlue)
        case .post?: return Color(nsColor: .systemOrange)
        case .delete?: return Color(nsColor: .systemRed)
        case .patch?: return Color(nsColor: .systemPurple)
        default: return .secondary
        }
    }
}
