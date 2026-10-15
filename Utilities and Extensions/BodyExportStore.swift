//
//  BodyExportStore.swift
//  App Traffic Inspector
//
//  Writes captured request bodies to a user-visible folder so copied cURL commands can
//  reference them with `@file`. The sandbox temp directory is avoided on purpose: Terminal
//  reading another app's container triggers macOS's "access data from other apps" prompt.
//

import AppKit
import Foundation

@MainActor
final class BodyExportStore: ObservableObject {
    static let shared = BodyExportStore()

    static let bookmarkKey = "bodyExportFolderBookmark"
    static let exportDirectoryPrefix = "transaction-"

    @Published private(set) var folderURL: URL
    @Published private(set) var isCustomFolder = false

    private var scopedURL: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folderURL = Self.defaultFolder
        #if DEBUG
        if UITestConfiguration.isUITesting {
            folderURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppTrafficInspector-UITests", isDirectory: true)
            return
        }
        #endif
        restoreBookmark()
    }

    /// `~/Downloads/AppTrafficInspector`, using the real home directory rather than the
    /// sandbox container so paths in cURL commands are usable from Terminal.
    static var defaultFolder: URL {
        realHomeDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("AppTrafficInspector", isDirectory: true)
    }

    private static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: Folder selection

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose where request bodies are written for copied cURL commands."
        panel.directoryURL = folderURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Self.bookmarkKey)
            stopAccessing()
            restoreBookmark()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func resetToDefault() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        stopAccessing()
        folderURL = Self.defaultFolder
        isCustomFolder = false
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    /// Removes only directories this app created, never other content in a user-chosen folder.
    @discardableResult
    func clearExportedFiles() -> Int {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for url in contents where url.lastPathComponent.hasPrefix(Self.exportDirectoryPrefix) {
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: Export

    /// Writes `data` to `<folder>/transaction-<id>/<filename>` and returns the file URL.
    func write(_ data: Data, filename: String, transactionId: String) throws -> URL {
        let directory = folderURL.appendingPathComponent(
            Self.exportDirectoryPrefix + BinaryFormatting.sanitizedFilename(transactionId),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(BinaryFormatting.sanitizedFilename(filename))
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: Bookmark lifecycle

    private func restoreBookmark() {
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            defaults.removeObject(forKey: Self.bookmarkKey)
            return
        }
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
        if isStale, let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: Self.bookmarkKey)
        }
        folderURL = url
        isCustomFolder = true
    }

    private func stopAccessing() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
