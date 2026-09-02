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
    @State private var showingDetails = false
    @State private var pin = ""
    @FocusState private var pinFocused: Bool
    @FocusState private var titleFocused: Bool

    public init(model: AppModel, itemID: UUID) {
        self.model = model
        self.itemID = itemID
    }

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Theme.hairline)

            if let snapshot, snapshot.isLocked {
                lockedNotice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }

            Divider().overlay(Theme.hairline)
            metadataFooter
        }
        .task(id: itemID) {
            load()
            showingDetails = false
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
                Divider()
                Toggle("Sensitive", isOn: Binding(
                    get: { snapshot?.isSensitive ?? false },
                    set: { model.setItemSensitive(itemID, $0) }
                ))
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
            PanelPreview(snapshot: snapshot, bodyText: filePreview.body,
                         fileURL: filePreview.fileURL, thumbnailURL: filePreview.thumbnailURL)
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

    private var filePreview: AppModel.PreviewData {
        model.previewData(for: itemID)
    }

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

            SecureField("PIN", text: $pin)
                // Plain, with our own well: the bordered style draws the system's
                // blue focus ring, which is the loudest thing in a monochrome app —
                // and AutoFill offers to fill a "Passwords…" suggestion over the top
                // of a field that wants a local PIN, not a website login.
                .textFieldStyle(.plain)
                .textContentType(nil)
                .multilineTextAlignment(.center)
                .focused($pinFocused)
                .onSubmit(submitPIN)
                .onChange(of: pin) { _, _ in model.pinError = nil }
                .padding(.horizontal, Theme.Space.s)
                .frame(width: 148, height: 28)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .strokeBorder(model.pinError == nil ? Theme.hairline : Theme.danger,
                                      lineWidth: 1)
                )

            if let error = model.pinError {
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
            pinFocused = true
            if model.vault.biometricsEnabled { Task { await model.tryBiometricUnlock() } }
        }
    }

    private func submitPIN() {
        if model.unlockInPlace(pin: pin) {
            pin = ""
            load()
        }
    }

    // MARK: - Metadata footer
    //
    // One quiet line, because none of this is why you opened the item. It expands
    // into real fields when you actually want to change something.

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.panelIn) { showingDetails.toggle() }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    if !showingDetails {
                        Label(snapshot?.folderPath.isEmpty == false
                              ? snapshot!.folderLabel : "No folder", systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text("Details")
                    }

                    // Only while collapsed: expanded, the Tags field below shows the
                    // same thing, and the item's tags were listed twice at once.
                    if !showingDetails, let tags = snapshot?.tagNames, !tags.isEmpty {
                        Text(tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        if tags.count > 3 { Text("+\(tags.count - 3)") }
                    }

                    Spacer(minLength: Theme.Space.s)

                    if let size = snapshot?.byteSize, size > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let uses = snapshot?.useCount, uses > 0 { Text("Used \(uses)×") }
                    Image(systemName: snapshot?.isSensitive == true ? "lock.fill" : "lock.open")
                    Image(systemName: showingDetails ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9))
                }
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, Theme.Space.l)
                .frame(height: 34)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showingDetails ? "Hide details" : "Show details")

            if showingDetails { detailFields }
        }
    }

    private var detailFields: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            field("Folder") {
                Picker("", selection: folderBinding) {
                    Text("No folder").tag(UUID?.none)
                    ForEach(model.store.allFolders(), id: \.id) { folder in
                        Text(folder.path.joined(separator: " › ")).tag(UUID?.some(folder.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            field("Tags") {
                TextField("Separated by commas", text: $tagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitTags)
            }
            field("Notes") {
                TextField("Anything worth remembering", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(commit)
            }
        }
        .font(Theme.Typography.body)
        .padding(.horizontal, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label)
                .font(Theme.Typography.meta)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 52, alignment: .leading)
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
