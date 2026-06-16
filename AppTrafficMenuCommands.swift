//
//  JSONHighlighter.swift
//  App Traffic Inspector
//
//  Created by Ernest Cunningham on 15/10/2025.
//

import SwiftUI

struct AppTrafficMenuCommands: Commands {
    @ObservedObject var store: AppTrafficStore

    init(store: AppTrafficStore) {
        self.store = store
    }

    var body: some Commands {
        // Keep default App, Edit, Window, Help menus from SwiftUI
        CommandGroup(replacing: .newItem) { }
        CommandGroup(after: .pasteboard) {
            Button("Clear Packets") { store.clearPackets() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        CommandGroup(after: .help) {
            Button("Quick Start…") {
                NotificationCenter.default.post(name: .showQuickStartGuide, object: nil)
            }
        }
    }
}
