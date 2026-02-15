import SwiftUI
import AppKit

@main
struct AppTrafficInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppTrafficStore()

    var body: some Scene {
        WindowGroup {
            AppTrafficRootView(store: store)
                .environmentObject(store)
        }
        .commands { AppTrafficMenuCommands(store: store) }
    }
}
