//
//  AppDelegate.swift
//  App Traffic Inspector
//

import Cocoa

private let mcpServerEnabledKey = "mcpServerEnabled"

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mcpServer: MCPServer?
    private var startStopObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {}

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        GetAppInfoTool.setLaunchTime(Date())
        let o1 = NotificationCenter.default.addObserver(forName: .mcpServerStart, object: nil, queue: .main) { [weak self] _ in
            self?.startMCPServer()
        }
        let o2 = NotificationCenter.default.addObserver(forName: .mcpServerStop, object: nil, queue: .main) { [weak self] _ in
            self?.stopMCPServer()
        }
        let o3 = NotificationCenter.default.addObserver(forName: .mcpServerDidStart, object: nil, queue: .main) { _ in
            Task { @MainActor in MCPServerStatus.shared.isMCPServerRunning = true }
        }
        let o4 = NotificationCenter.default.addObserver(forName: .mcpServerDidStop, object: nil, queue: .main) { _ in
            Task { @MainActor in MCPServerStatus.shared.isMCPServerRunning = false }
        }
        startStopObservers = [o1, o2, o3, o4]
        if UserDefaults.standard.bool(forKey: mcpServerEnabledKey) {
            startMCPServer()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        stopMCPServer()
        for o in startStopObservers {
            NotificationCenter.default.removeObserver(o)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in sender.windows {
            window.orderFront(self)
        }
        return true
    }

    private func startMCPServer() {
        if mcpServer == nil {
            mcpServer = MCPServer()
        }
        mcpServer?.start()
        // isMCPServerRunning is set to true only when MCPServer posts .mcpServerDidStart (listener .ready)
        // and set to false on .mcpServerDidStop (listener .failed or .cancelled)
    }

    private func stopMCPServer() {
        mcpServer?.stop()
        mcpServer = nil
        Task { @MainActor in
            MCPServerStatus.shared.isMCPServerRunning = false
        }
    }
}
