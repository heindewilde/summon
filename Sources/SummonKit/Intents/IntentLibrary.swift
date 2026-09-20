#if canImport(AppIntents)
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// A read-only door into the library, for the places that are not the app.
///
/// Intents, widgets and the Control Centre all run in short-lived processes that may
/// never have shown a window. They need the same two answers — what is in the library,
/// and what does this item contain — and nothing else: no search index, no clipboard
/// monitor, no vault timers, no CloudKit container.
///
/// Sealed items are refused rather than skipped quietly. An intent has nowhere to ask
/// for a PIN, so "open Summon to use this" is the honest reply, and the alternative —
/// a shortcut that reads a sealed passport scan — is the hole the vault exists to
/// prevent.
@MainActor
public final class IntentLibrary {
    private static var cached: IntentLibrary?

    private let store: LibraryStore

    /// One per process. Opening a SwiftData container is the expensive part, and a
    /// widget timeline asks for several items in a row.
    public static func shared() throws -> IntentLibrary {
        if let cached { return cached }
        let library = try IntentLibrary()
        cached = library
        return library
    }

    private init() throws {
        let paths = LibraryPaths.standard()
        // Never migrates and never mirrors, for the same reasons `Ingestion` does not.
        store = try LibraryStore(paths: paths, vault: Vault(paths: paths),
                                 syncs: false, migrates: false)
    }

    public var snapshots: [ItemSnapshot] { store.snapshots }

    public var pinned: [ItemSnapshot] {
        store.snapshots.filter(\.isPinned).sorted { $0.title < $1.title }
    }

    /// The contents of an item, when they can be given without asking a question.
    /// Nil for a locked item, and for one with fill-in fields still to fill.
    public func payload(for id: UUID) -> InsertPayload? {
        guard let snapshot = store.snapshots.first(where: { $0.id == id }),
              !snapshot.isLocked, !snapshot.hasPlaceholders
        else { return nil }
        return store.payload(for: id)
    }

    public func refresh() { store.refresh() }
}

/// Writing to the clipboard, which is the one thing every one of these surfaces does.
public enum Pasteboard {
    public static func write(_ payload: InsertPayload) {
        #if canImport(AppKit)
        let board = NSPasteboard.general
        board.clearContents()
        if let text = payload.plainText { board.setString(text, forType: .string) }
        #elseif canImport(UIKit)
        if let text = payload.plainText {
            UIPasteboard.general.string = text
        } else if let data = payload.imageData {
            UIPasteboard.general.image = UIImage(data: data)
        }
        #endif
    }
}
#endif
