import Foundation
import Combine

final class AppTrafficStore: ObservableObject {
    @Published var projects: [AppTrafficProject] = []
    @Published var selectedProject: AppTrafficProject?
    @Published var devices: [AppTrafficDevice] = []
    @Published var selectedDevice: AppTrafficDevice?
    @Published var packets: [AppTrafficPacket] = []
    @Published var selectedPacket: AppTrafficPacket?

    @Published var addressFilterTerm: String = "" { didSet { refreshPackets() } }
    @Published var methodFilterTerm: String = "" { didSet { refreshPackets() } }
    @Published var statusFilterTerm: String = "" { didSet { refreshPackets() } }

    private var cancellables: [NSObjectProtocol] = []

    init() {
        subscribeNotifications()
        refreshAll()
    }

    deinit {
        for token in cancellables { NotificationCenter.default.removeObserver(token) }
    }

    func select(project: AppTrafficProject) {
        AppTrafficController.shared.selectedProject = project
        refreshAll()
    }

    func select(device: AppTrafficDevice) {
        AppTrafficController.shared.selectedProject?.selectedDevice = device
        refreshAll()
    }

    func select(packet: AppTrafficPacket?) {
        AppTrafficController.shared.selectedProject?.selectedDevice?.select(packet: packet)
        refreshSelection()
    }

    func clearPackets() {
        AppTrafficController.shared.selectedProject?.selectedDevice?.clear()
        refreshPackets()
    }

    private func subscribeNotifications() {
        let center = NotificationCenter.default
        let didGet = center.addObserver(forName: AppTrafficNotifications.didGetPacket, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAll()
        }
        let didUpdate = center.addObserver(forName: AppTrafficNotifications.didUpdatePacket, object: nil, queue: .main) { [weak self] _ in
            self?.refreshPackets()
        }
        let didSelectProject = center.addObserver(forName: AppTrafficNotifications.didSelectProject, object: nil, queue: .main) { [weak self] _ in
            self?.refreshProjectsAndDevices()
        }
        let didSelectDevice = center.addObserver(forName: AppTrafficNotifications.didSelectDevice, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDevicesAndPackets()
        }
        let didSelectPacket = center.addObserver(forName: AppTrafficNotifications.didSelectPacket, object: nil, queue: .main) { [weak self] _ in
            self?.refreshSelection()
        }
        cancellables.append(contentsOf: [didGet, didUpdate, didSelectProject, didSelectDevice, didSelectPacket])
    }

    private func refreshAll() {
        refreshProjectsAndDevices()
        refreshDevicesAndPackets()
        refreshSelection()
    }

    private func refreshProjectsAndDevices() {
        projects = AppTrafficController.shared.projects
        selectedProject = AppTrafficController.shared.selectedProject
        devices = selectedProject?.devices ?? []
        selectedDevice = selectedProject?.selectedDevice
    }

    private func refreshDevicesAndPackets() {
        selectedProject = AppTrafficController.shared.selectedProject
        devices = selectedProject?.devices ?? []
        selectedDevice = selectedProject?.selectedDevice
        refreshPackets()
    }

    private func refreshPackets() {
        let all = AppTrafficController.shared.selectedProject?.selectedDevice?.packets ?? []
        packets = filter(items: all)
        selectedPacket = AppTrafficController.shared.selectedProject?.selectedDevice?.selectedPacket
    }

    private func refreshSelection() {
        selectedProject = AppTrafficController.shared.selectedProject
        selectedDevice = selectedProject?.selectedDevice
        selectedPacket = selectedDevice?.selectedPacket
    }

    private func filter(items: [AppTrafficPacket]) -> [AppTrafficPacket] {
        var filtered = performAddressFiltration(items)
        filtered = performMethodFiltration(filtered)
        filtered = performStatusFiltration(filtered)
        return filtered
    }

    private func performAddressFiltration(_ items: [AppTrafficPacket]) -> [AppTrafficPacket] {
        guard !addressFilterTerm.isEmpty else { return items }
        return items.filter { $0.requestInfo?.url?.contains(addressFilterTerm) ?? true }
    }

    private func performMethodFiltration(_ items: [AppTrafficPacket]) -> [AppTrafficPacket] {
        guard !methodFilterTerm.isEmpty else { return items }
        return items.filter { $0.requestInfo?.requestMethod?.rawValue.lowercased().contains(methodFilterTerm.lowercased()) ?? true }
    }

    private func performStatusFiltration(_ items: [AppTrafficPacket]) -> [AppTrafficPacket] {
        guard !statusFilterTerm.isEmpty else { return items }
        let trimmed = statusFilterTerm.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return items.filter { ($0.requestInfo?.statusCode?.trimmingCharacters(in: .whitespaces).isEmpty) ?? true }
        }
        return items.filter { $0.requestInfo?.statusCode?.contains(statusFilterTerm) ?? false }
    }
}
