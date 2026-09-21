// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import QuickLook
import SummonKit
import SummonUI
import SwiftUI

/// One item, read before it is changed.
///
/// A phone is a device you hold while doing something else, and an editor that is
/// always live is an editor you nudge by accident — usually on the item you were about
/// to paste. So this reads, with Copy and Share where a thumb already is, and Edit is
/// a deliberate step.
struct PhoneItemDetailView: View {
    @Bindable var model: AppModel
    let itemID: UUID

    @State private var editing = false
    @State private var previewURL: URL?
    @State private var body_ = ""
    @State private var preview = AppModel.PreviewData()

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                // The item was deleted, here or on another device. Saying so beats a
                // blank screen that looks like a failure to load.
                ContentUnavailableView("This item is gone", systemImage: "trash",
                                       description: Text("It was deleted."))
            }
        }
        .background(GlassBackground(material: .underWindowBackground, bloom: 0.4))
        .navigationTitle(snapshot?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let snapshot, !snapshot.isLocked {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PhoneItemMenu(model: model, item: snapshot ?? .init(id: itemID, title: "")) {}
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) {
            PhoneItemEditView(model: model, itemID: itemID) { editing = false }
        }
        .quickLookPreview($previewURL)
        .task(id: itemID) { reload() }
        .onChange(of: model.store.revision) { _, _ in reload() }
    }

    @ViewBuilder
    private func content(_ snapshot: ItemSnapshot) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(snapshot)

                    if snapshot.isLocked {
                        locked
                    } else if snapshot.kind.isTextual {
                        Text(body_.isEmpty ? "Empty" : body_)
                            .font(Theme.Typography.heading)
                            .foregroundStyle(body_.isEmpty ? Theme.faintText : Theme.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        filePreview(snapshot)
                    }
                }
                .padding(Theme.Space.l)
            }

            actionBar(snapshot)
        }
    }

    private func header(_ snapshot: ItemSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                KindGlyph(kind: snapshot.kind, isLocked: snapshot.isLocked, size: 20)
                Text(snapshot.kind.displayName)
                if snapshot.isPinned { Label("Pinned", systemImage: "pin.fill").labelStyle(.iconOnly) }
                if snapshot.hasPlaceholders {
                    Label("Fill-in fields", systemImage: "square.dashed.inset.filled")
                }
            }
            .font(Theme.Typography.meta)
            .foregroundStyle(Theme.tertiaryText)

            if !snapshot.folderPath.isEmpty || !snapshot.tagNames.isEmpty {
                FlowLayout(spacing: Theme.Space.xs) {
                    if !snapshot.folderPath.isEmpty {
                        chip(snapshot.folderPath.joined(separator: " › "), symbol: "folder")
                    }
                    ForEach(snapshot.tagNames, id: \.self) { chip("#\($0)", symbol: nil) }
                }
            }
        }
    }

    private func chip(_ text: String, symbol: String?) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2) }
            Text(text)
        }
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
    }

    private var locked: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.accent)
            Text("This item is locked")
                .font(Theme.Typography.display)
            Text("Its title stays searchable. Its contents do not.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.secondaryText)
            Button("Unlock") { model.use(itemID, style: .copy) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
    }

    @ViewBuilder
    private func filePreview(_ snapshot: ItemSnapshot) -> some View {
        VStack(spacing: Theme.Space.m) {
            if let url = preview.thumbnailURL ?? preview.fileURL,
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large))
            }
            if let text = preview.body, !text.isEmpty {
                Text(text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if preview.fileURL != nil {
                Button {
                    previewURL = preview.fileURL
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Copy and Share, on glass, within reach of a thumb. These are what an item is
    /// *for*; everything else is behind the menu.
    private func actionBar(_ snapshot: ItemSnapshot) -> some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                model.use(itemID, style: .copy)
                if !snapshot.isLocked, !snapshot.hasPlaceholders { Theme.Haptics.success() }
            } label: {
                Label(snapshot.hasPlaceholders ? "Fill in & Copy" : "Copy", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.s)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            if !snapshot.isLocked {
                // A file shares as the file; a snippet shares as its text. Sharing a
                // snippet used to be impossible because only files have a URL, which
                // left the most common kind of item in the library with no way out of
                // the app except the clipboard.
                if let url = preview.fileURL {
                    ShareLink(item: url) { shareLabel }.buttonStyle(.bordered)
                } else if !body_.isEmpty {
                    ShareLink(item: body_) { shareLabel }.buttonStyle(.bordered)
                }
            }
        }
        .padding(Theme.Space.l)
        .background(.bar)
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .frame(maxWidth: 110)
            .padding(.vertical, Theme.Space.s)
    }

    private func reload() {
        preview = model.previewData(for: itemID)
        guard let item = model.store.item(id: itemID) else { return }
        body_ = model.store.resolveBodyText(item, key: model.vault.currentKey) ?? ""
    }
}
#endif
