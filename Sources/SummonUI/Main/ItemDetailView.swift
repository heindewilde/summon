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
    @State private var tags: [String] = []
    @State private var loadedID: UUID?
    @State private var rewriting = false
    @State private var pin = ""
    @FocusState private var titleFocused: Bool
    @State private var filePreview: AppModel.PreviewData?

    public init(model: AppModel, itemID: UUID) {
        self.model = model
        self.itemID = itemID
    }

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    /// What has to change before the pane reloads: the item, or whether it can be
    /// read at all.
    private struct LoadKey: Equatable {
        let itemID: UUID
        let isLocked: Bool
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Theme.hairline)

            if let snapshot, snapshot.isLocked {
                lockedNotice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A floor under the editor: the form below sizes to its content and
                // will not compress, so in a short window it would otherwise take the
                // space the thing you came to read was using.
                content.frame(minHeight: 140)
            }

            Divider().overlay(Theme.hairline)
            properties
        }
        // Keyed on the lock state as well as the item. Unlocking does not change which
        // item is selected, so this never re-ran: the body stayed at whatever the
        // locked snapshot had — nothing — and an image's preview stayed nil. Clicking
        // away and back re-selected the item, which is why that appeared to fix it.
        .task(id: LoadKey(itemID: itemID, isLocked: snapshot?.isLocked ?? false)) {
            load()
            filePreview = nil
            if let snapshot, !snapshot.kind.isTextual, !snapshot.isLocked {
                filePreview = model.previewData(for: itemID)
            }
            // A snippet created from the + menu exists already and is selected; the
            // cursor lands in its title so you can just start typing.
            if model.focusNewItemTitle {
                model.focusNewItemTitle = false
                titleFocused = true
            }
        }
        .onDisappear {
            commit()
            // A new snippet left completely untouched is removed again, so abandoning
            // one does not litter the library with blanks.
            model.discardIfEmpty(itemID)
        }
    }

    // MARK: - Title bar
    //
    // The item's name, and the two things you do to an item often enough to deserve
    // being visible. Everything else is behind the overflow menu — a window has room
    // to show its actions, which is why the panel's ⌘K does not appear here.

    private var titleBar: some View {
        HStack(spacing: Theme.Space.s) {
            KindGlyph(kind: snapshot?.kind ?? .file, isLocked: snapshot?.isLocked ?? false, size: 16)

            TextField("Untitled", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .focused($titleFocused)
                .onSubmit(commit)

            Spacer(minLength: Theme.Space.s)

            Button {
                model.togglePin(itemID)
            } label: {
                Image(systemName: snapshot?.isPinned == true ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(snapshot?.isPinned == true ? Theme.primaryText : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .help(snapshot?.isPinned == true ? "Unpin" : "Pin to the top of the panel")
            .accessibilityLabel(snapshot?.isPinned == true ? "Unpin" : "Pin")

            Menu {
                Button("Copy", systemImage: "doc.on.doc") { model.use(itemID, style: .copy) }
                if snapshot?.kind.isBlobBacked == true {
                    Button("Open", systemImage: "arrow.up.forward.app") { model.use(itemID, style: .open) }
                    Button("Reveal in Finder", systemImage: "folder") { model.revealInFinder(itemID) }
                }
                // No Sensitive toggle here: it is a row in the properties below, and
                // a second switch for the same thing two inches away is a question
                // about which one is authoritative.
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.mainSelection = itemID
                    model.requestDeleteSelected()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: 52)
    }

    // MARK: - Content
    //
    // The body owns the window. It used to sit inside a bordered card, under a
    // CONTENT label, above four more labelled fields all at the same weight — so the
    // thing you came to read had no more presence than the folder picker.

    @ViewBuilder
    private var content: some View {
        if let snapshot, snapshot.kind.isTextual {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if snapshot.kind == .richText {
                        SnippetEditor(attributed: $attributed)
                            .onChange(of: attributed) { _, _ in scheduleCommit() }
                    } else {
                        TextEditor(text: $body_)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .onChange(of: body_) { _, _ in scheduleCommit() }
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if snapshot.hasPlaceholders || snapshot.kind == .richText || rewriteAvailable {
                    contentAffordances(snapshot)
                }
            }
        } else if let snapshot {
            PanelPreview(snapshot: snapshot, bodyText: filePreview?.body,
                         fileURL: filePreview?.fileURL, thumbnailURL: filePreview?.thumbnailURL,
                         showsTags: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The row under the editor: only what applies to this item, and nothing when
    /// none of it does.
    private func contentAffordances(_ snapshot: ItemSnapshot) -> some View {
        HStack(spacing: Theme.Space.m) {
            if snapshot.hasPlaceholders {
                Label("Fill-in fields", systemImage: "square.dashed.inset.filled")
                    .labelStyle(.titleAndIcon)
                    .help("Use {{name}}, {{name:default}}, {{date}}, {{clipboard}} or {{cursor}}")
            }
            if snapshot.kind == .richText {
                Label("Formatted", systemImage: "textformat").labelStyle(.titleAndIcon)
            }
            Spacer()
            if rewriteAvailable {
                if rewriting {
                    ProgressView().controlSize(.small)
                } else {
                    Menu("Rewrite") {
                        ForEach(RewriteTone.allCases, id: \.self) { tone in
                            Button(tone.rawValue) { rewrite(tone) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .font(Theme.Typography.meta)
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.s)
    }

    private var rewriteAvailable: Bool {
        snapshot?.kind.isTextual == true && snapshot?.isLocked == false
            && model.intelligence.status.isReady
    }

    /// Resolved in `.task`, never in `body`. Read from `body` it ran a full sorted
    /// SwiftData fetch plus a decrypt — and for a sealed blob a decrypt-to-disk — on
    /// every render, which is what made clicking between items feel heavy.

    /// The PIN field sits where the content would be. Summoning the panel to ask for
    /// a PIN meant a window appeared over the thing you were already looking at.
    private var lockedNotice: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "lock.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.tertiaryText)
            Text("Contents are encrypted")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.primaryText)

            // The same four boxes the sheet uses, resolving on the fourth digit. A
            // single text field needing a return was one more thing to know, and a
            // different thing from every other PIN prompt in the app.
            //
            // Hidden while a sheet is already asking: two PIN prompts on screen at
            // once, one of them inert behind the other, is not a question anyone can
            // answer confidently.
            if model.pinSheet == nil {
                PINField(digits: $pin, isError: model.pinError != nil, onComplete: submitPIN)
                    .onChange(of: pin) { _, _ in model.pinError = nil }
            }

            if model.pinSheet != nil {
                EmptyView()
            } else if let error = model.pinError {
                Text(error)
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.danger)
            } else if Vault.biometricsAvailable && model.vault.biometricsEnabled {
                Button("Use Touch ID") { Task { await model.tryBiometricUnlock() } }
                    .buttonStyle(.link)
                    .font(Theme.Typography.meta)
            } else {
                Text("Unlocks everything sensitive until it re-locks.")
                    .font(Theme.Typography.meta)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .onAppear {
            if model.vault.biometricsEnabled { Task { await model.tryBiometricUnlock() } }
        }
    }

    private func submitPIN() {
        if model.unlockInPlace(pin: pin) {
            pin = ""
            load()
        }
    }

    // MARK: - Properties
    //
    // A real `Form`, so the label column, the row separators and the control sizing
    // are Apple's rather than three numbers chosen by eye. It replaces a collapsing
    // summary bar that wrapped onto three lines in a narrow pane and repeated what
    // the preview above it was already showing.

    private var properties: some View {
        // A `Grid`, not a `Form`. A form row aligns its label to the *first text
        // baseline* of its content, and the tag well has no text baseline to find —
        // so "Tags" sat level with the bottom of its own field while every other
        // label sat level with the middle of its. A grid centres each row and gives
        // one shared label column, which is what the eye was looking for.
        Grid(alignment: .leading,
             horizontalSpacing: Theme.Space.m,
             verticalSpacing: 10) {
            GridRow {
                label("Folder")
                Picker("", selection: folderBinding) {
                    Label("No folder", systemImage: "tray").tag(UUID?.none)
                    ForEach(model.folderChoicesForPicker, id: \.id) { choice in
                        Label(choice.label, systemImage: choice.symbolName).tag(choice.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Lifted above the rows below it, so the suggestion menu draws over Notes
            // and Sensitive instead of being painted on by them.
            GridRow {
                label("Tags")
                TagField(tags: $tags,
                         suggestions: model.knownTagNames,
                         counts: model.knownTagCounts,
                         initialDraft: model.tagDraftForCapture,
                         onChange: commitTags)
                    // Rebuilt per item, so a half-typed tag never carries across a
                    // change of selection.
                    .id(itemID)
            }
            .zIndex(1)

            GridRow {
                label("Notes")
                TextField("", text: $notes,
                          prompt: Text("Anything worth remembering"), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .multilineTextAlignment(.leading)
                    .onSubmit(commit)
            }

            GridRow {
                label("Sensitive")
                HStack(spacing: Theme.Space.s) {
                    Toggle("", isOn: Binding(
                        get: { snapshot?.isSensitive ?? false },
                        set: { model.setItemSensitive(itemID, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    // The system accent was the only saturated colour in the pane, on
                    // the one control that is not trying to be noticed.
                    .tint(Theme.primaryText)
                    .disabled(inheritsSensitivity)

                    // The switch says on or off; the padlock says what "on" means, in
                    // the glyph the sidebar and the panel already use for it.
                    if snapshot?.isSensitive == true {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                            .transition(.opacity)
                            .accessibilityLabel("Encrypted")
                    }
                    Spacer(minLength: 0)
                }
                .animation(Theme.panelIn, value: snapshot?.isSensitive)
                .help(inheritsSensitivity
                      ? "Its folder is sensitive, so everything inside it is encrypted."
                      : "Encrypt this item’s contents behind your PIN.")
            }

            // Only where it means something. A snippet's byte count is noise; a file's
            // size is the one fact about it you might actually want.
            if snapshot?.kind.isBlobBacked == true, let size = snapshot?.byteSize, size > 0 {
                GridRow {
                    label("Size")
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(Theme.Typography.body)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.m)
        // More room under the last row than above the first: it is the window's edge
        // down there, not another section, and 12pt against a hard edge reads as the
        // block having been cut off.
        .padding(.bottom, Theme.Space.l)
    }

    /// One label column, right-aligned against the fields.
    ///
    /// Every row is given the same minimum height so the block has one rhythm: the
    /// bezelled fields set their own height and the bare ones — the switch, the size —
    /// used to collapse to the height of their text, which is what made the bottom
    /// two rows look crammed against the rest.
    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.secondaryText)
            .gridColumnAlignment(.trailing)
            .frame(minHeight: Self.rowHeight)
    }

    private static let rowHeight: CGFloat = 24

    /// True when the item is sensitive only because its folder is: the switch would
    /// promise something it cannot deliver, since the folder decides.
    private var inheritsSensitivity: Bool {
        guard let item = model.store.item(id: itemID) else { return false }
        return !item.isSensitive && item.isEffectivelySensitive
    }

    private var folderBinding: Binding<UUID?> {
        Binding(
            get: { model.store.item(id: itemID)?.folder?.id },
            set: { newID in
                guard let item = model.store.item(id: itemID) else { return }
                model.fileItem(item.id, intoFolderID: newID)
            }
        )
    }

    // MARK: - Loading and saving

    private func load() {
        guard let item = model.store.item(id: itemID) else { return }
        loadedID = itemID
        title = item.title
        notes = item.notes
        tags = item.tagNames
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

    private func commitTags(_ names: [String]) {
        // `loadedID` is the item these tags were actually loaded from; without it a
        // late commit from the previous selection lands on the current one.
        guard loadedID == itemID,
              let item = model.store.item(id: itemID),
              item.tagNames != names.sorted() else { return }
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
