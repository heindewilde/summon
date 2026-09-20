// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// Nothing to show, said usefully.
///
/// Three different nothings, and they want three different answers: an empty library
/// wants to be filled, a filter that matches nothing wants clearing, and a search that
/// found nothing wants to say so without implying the library is empty. The shared
/// `EmptyStateView` offered one message and a button that did nothing on iOS.
struct PhoneEmptyState: View {
    @Bindable var model: AppModel
    let isSearching: Bool

    private var isFiltered: Bool { model.sidebarSelection != .all }
    private var libraryIsEmpty: Bool { model.store.snapshots.isEmpty }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.9))
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.s) {
                Text(title)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.primaryText)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            action
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        if isSearching { return "magnifyingglass" }
        if isFiltered { return "line.3.horizontal.decrease.circle" }
        return "tray"
    }

    private var title: String {
        if isSearching { return "Nothing found" }
        if isFiltered { return "Nothing filed here" }
        return libraryIsEmpty ? "Your library is empty" : "Nothing to show"
    }

    private var message: String {
        if isSearching {
            return "No item matches “\(model.mainSearch)”. Titles, contents and the text inside PDFs and images are all searched."
        }
        if isFiltered {
            return "Items you file here will appear in this filter."
        }
        return """
        Summon holds the handful of things you reuse: the reply you keep rewriting, \
        the IBAN, the passport scan. Add one, or open Summon on your Mac — your \
        library follows you.
        """
    }

    @ViewBuilder
    private var action: some View {
        if isSearching {
            Button("Clear search") { model.mainSearch = ""; model.runSearch() }
                .buttonStyle(.bordered)
        } else if isFiltered {
            Button("Show everything") { model.sidebarSelection = .all; model.runSearch() }
                .buttonStyle(.bordered)
        } else {
            VStack(spacing: Theme.Space.s) {
                Button {
                    model.beginNewSnippet()
                } label: {
                    Label("New snippet", systemImage: "square.and.pencil")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.presentImportPanel()
                } label: {
                    Label("Choose files", systemImage: "folder")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await model.saveClipboard() }
                } label: {
                    Label("Save what I copied", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.bordered)
            }
            .tint(Theme.accent)
        }
    }
}
#endif
