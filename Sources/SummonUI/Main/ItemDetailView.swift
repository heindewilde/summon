import AppKit
import SwiftUI
import SummonKit

/// The right-hand editor. Where an item is refined, not where it is used.
public struct ItemDetailView: View {
    @Bindable var model: AppModel
    let itemID: UUID

    @State private var title = ""
    @State private var body_ = ""
    @State private var attributed = NSAttributedString(string: "")
    @State private var notes = ""
    @State private var tagText = ""
    @State private var loadedID: UUID?
    @State private var rewriting = false

    public init(model: AppModel, itemID: UUID) {
        self.model = model
        self.itemID = itemID
    }

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    public var body: some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header
                if let snapshot, snapshot.isLocked {
                    lockedNotice
                } else {
                    contentEditor
                }
                metadataSection
                actionsSection
            }
            .padding(Theme.Space.m)
        }
        .task(id: itemID) { load() }
        .onDisappear(perform: commit)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            ThumbnailView(itemID: itemID, kind: snapshot?.kind ?? .file,
                          isLocked: snapshot?.isLocked ?? false,
                          thumbnailURL: model.thumbnailURL(for: itemID), size: 44)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .onSubmit(commit)

                HStack(spacing: Theme.Space.xs) {
                    Text(snapshot?.kind.displayName ?? "")
                    if let size = snapshot?.byteSize, size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let uses = snapshot?.useCount, uses > 0 {
                        Text("Used \(uses)×")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiaryText)
            }

            Spacer()

            Button {
                model.togglePin(itemID)
            } label: {
                Image(systemName: snapshot?.isPinned == true ? "pin.fill" : "pin")
                    .foregroundStyle(snapshot?.isPinned == true ? Theme.spark : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help(snapshot?.isPinned == true ? "Unpin" : "Pin to the top of the panel")
        }
    }

    private var lockedNotice: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.spark)
            VStack(alignment: .leading, spacing: 1) {
                Text("Contents are encrypted").font(.system(size: 12, weight: .medium))
                Text("Unlock to view or edit this item.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button("Unlock") { model.summonForUnlock() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(Theme.Space.s)
        .cardBackground()
    }

    @ViewBuilder
    private var contentEditor: some View {
        if let snapshot, snapshot.kind.isTextual {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text("CONTENT")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    if snapshot.kind == .richText {
                        Label("Formatting preserved", systemImage: "textformat")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.secondaryText)
                            .labelStyle(.titleAndIcon)
                    }
                    if snapshot.hasPlaceholders {
                        Label("Has fill-in fields", systemImage: "square.dashed.inset.filled")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Group {
                    if snapshot.kind == .richText {
                        SnippetEditor(attributed: $attributed)
                            .onChange(of: attributed) { _, _ in scheduleCommit() }
                    } else {
                        TextEditor(text: $body_)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Space.xs)
                            .onChange(of: body_) { _, _ in scheduleCommit() }
                    }
                }
                .frame(minHeight: 180)
                .cardBackground(raised: true)

                Text("Use {{name}} for a fill-in field, {{name:default}} for one with a default, and {{date}}, {{clipboard}} or {{cursor}} for the rest.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let snapshot {
            filePreviewCard(snapshot)
        }
    }

    private func filePreviewCard(_ snapshot: ItemSnapshot) -> some View {
        let data = model.previewData(for: itemID)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            PanelPreview(snapshot: snapshot, bodyText: data.body,
                         fileURL: data.fileURL, thumbnailURL: data.thumbnailURL)
                .frame(height: 300)
                .cardBackground()
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            labelled("TAGS") {
                TextField("Add tags, separated by commas", text: $tagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, 5)
                    .cardBackground(radius: Theme.Radius.small, raised: true)
                    .onSubmit(commitTags)
            }

            labelled("FOLDER") {
                Picker("", selection: folderBinding) {
                    Text("No folder").tag(UUID?.none)
                    ForEach(model.store.allFolders(), id: \.id) { folder in
                        Text(folder.path.joined(separator: " › ")).tag(UUID?.some(folder.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            labelled("NOTES") {
                TextField("Anything you want to remember about this", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .lineLimit(1...4)
                    .padding(.horizontal, Theme.Space.xs)
                    .padding(.vertical, 5)
                    .cardBackground(radius: Theme.Radius.small, raised: true)
                    .onSubmit(commit)
            }

            Toggle(isOn: Binding(
                get: { snapshot?.isSensitive ?? false },
                set: { model.setItemSensitive(itemID, $0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sensitive").font(.system(size: 12, weight: .medium))
                    Text("Encrypts the contents. The title stays visible so you can still find it.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Button("Copy", systemImage: "doc.on.doc") { model.use(itemID, style: .copy) }
                if snapshot?.kind.isBlobBacked == true {
                    Button("Open", systemImage: "arrow.up.forward.app") { model.use(itemID, style: .open) }
                    Button("Reveal", systemImage: "folder") { model.revealInFinder(itemID) }
                }
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.deleteItem(itemID)
                    model.mainSelection = nil
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if snapshot?.kind.isTextual == true, model.intelligence.status.isReady,
               snapshot?.isLocked == false {
                HStack(spacing: Theme.Space.xs) {
                    Text("REWRITE")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                    ForEach(RewriteTone.allCases, id: \.self) { tone in
                        Button(tone.rawValue) { rewrite(tone) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(rewriting)
                    }
                    if rewriting { ProgressView().controlSize(.small) }
                }
                .padding(.top, Theme.Space.xxs)
            }
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
    }

    private var folderBinding: Binding<UUID?> {
        Binding(
            get: { model.store.item(id: itemID)?.folder?.id },
            set: { newID in
                guard let item = model.store.item(id: itemID) else { return }
                let folder = newID.flatMap { id in model.store.allFolders().first { $0.id == id } }
                model.store.move(item, to: folder)
                model.runSearch()
            }
        )
    }

    // MARK: - Loading and saving

    private func load() {
        guard let item = model.store.item(id: itemID) else { return }
        loadedID = itemID
        title = item.title
        notes = item.notes
        tagText = item.tagNames.joined(separator: ", ")
        body_ = model.store.resolveBodyText(item, key: model.vault.currentKey) ?? ""
        attributed = model.store.resolveAttributed(item, key: model.vault.currentKey)
            ?? NSAttributedString(string: "")
    }

    private func scheduleCommit() {
        // Editing writes through after a beat, so typing never blocks on a save.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard loadedID == itemID else { return }
            commit()
        }
    }

    private func commit() {
        guard let item = model.store.item(id: itemID), loadedID == itemID else { return }
        var changed = false
        if item.title != title, !title.isEmpty { item.title = title; changed = true }
        if item.notes != notes { item.notes = notes; changed = true }

        if item.kind == .richText {
            let current = model.store.resolveAttributed(item, key: model.vault.currentKey)
            if current != attributed, attributed.length > 0 {
                model.store.updateSnippet(item, attributed: attributed)
                changed = true
            }
        } else if item.kind.isTextual {
            let current = model.store.resolveBodyText(item, key: model.vault.currentKey) ?? ""
            if current != body_ {
                model.store.updateSnippet(item, plain: body_)
                changed = true
            }
        }
        if changed {
            item.updatedAt = Date()
            model.store.save()
            model.store.refresh()
            model.runSearch()
        }
    }

    private func commitTags() {
        guard let item = model.store.item(id: itemID) else { return }
        let names = tagText.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        model.store.setTags(item, names: names)
        model.runSearch()
    }

    private func rewrite(_ tone: RewriteTone) {
        rewriting = true
        Task {
            defer { rewriting = false }
            guard let rewritten = await model.intelligence.rewrite(body_, tone: tone) else {
                model.show(Toast(text: "Rewrite unavailable", symbol: "sparkles",
                                 tone: .warning, detail: model.intelligence.status.explanation))
                return
            }
            if let item = model.store.item(id: itemID), item.kind == .richText {
                // Keep it rich: swap the words, keep the run attributes of the start.
                let updated = NSMutableAttributedString(attributedString: attributed)
                let whole = NSRange(location: 0, length: updated.length)
                let attrs = updated.length > 0 ? updated.attributes(at: 0, effectiveRange: nil) : [:]
                updated.replaceCharacters(in: whole, with: NSAttributedString(string: rewritten, attributes: attrs))
                attributed = updated
            } else {
                body_ = rewritten
            }
            commit()
            model.show(Toast(text: "Rewritten — \(tone.rawValue.lowercased())",
                             symbol: "wand.and.sparkles", tone: .success,
                             detail: "⌘Z in the editor to undo"))
        }
    }
}
