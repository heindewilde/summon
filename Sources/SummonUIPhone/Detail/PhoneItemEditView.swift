// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// Changing an item, deliberately.
///
/// A sheet rather than a mode on the detail screen, so leaving it is a decision and
/// Cancel means something. Nothing is written until Save — the Mac's detail pane
/// commits as you type, which is right for a window you can see the library behind,
/// and wrong for a phone where the same gesture that scrolls can also edit.
struct PhoneItemEditView: View {
    @Bindable var model: AppModel
    let itemID: UUID
    let dismiss: () -> Void

    @State private var title = ""
    @State private var body_ = ""
    @State private var attributed = NSAttributedString(string: "")
    @State private var notes = ""
    @State private var tags: [String] = []
    @State private var folderID: UUID?
    @State private var isPinned = false
    @State private var isSensitive = false
    @State private var loaded = false

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    private var isRichText: Bool { snapshot?.kind == .richText }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .font(Theme.Typography.heading)
                }

                if let snapshot, snapshot.kind.isTextual {
                    Section("Content") {
                        if isRichText {
                            RichTextView(text: $attributed)
                                .frame(minHeight: 180)
                        } else {
                            TextEditor(text: $body_)
                                .frame(minHeight: 180)
                                .font(Theme.Typography.heading)
                        }
                    }
                }

                Section("Filing") {
                    Picker("Folder", selection: $folderID) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.store.allFolders(), id: \.id) { folder in
                            Text(folder.name).tag(UUID?.some(folder.id))
                        }
                    }
                    TagField(tags: $tags,
                             suggestions: model.store.allTags().map(\.name),
                             counts: model.knownTagCounts,
                             onChange: { tags = $0 })
                }

                Section {
                    Toggle("Pinned", isOn: $isPinned)
                    Toggle("Sensitive", isOn: $isSensitive)
                } footer: {
                    Text("A sensitive item is encrypted on this device. Its title stays searchable; its contents do not.")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...6)
                }

                Section {
                    Button("Delete Item", role: .destructive) {
                        dismiss()
                        model.requestDelete(itemID)
                    }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold()
                }
            }
            .task { load() }
        }
    }

    private func load() {
        guard !loaded, let item = model.store.item(id: itemID) else { return }
        loaded = true
        title = item.title
        notes = item.notes
        tags = item.tagNames
        folderID = item.folder?.id
        isPinned = item.isPinned
        isSensitive = item.isSensitive
        body_ = model.store.resolveBodyText(item, key: model.vault.currentKey) ?? ""
        attributed = model.store.resolveAttributed(item, key: model.vault.currentKey)
            ?? NSAttributedString(string: body_)
    }

    private func save() {
        guard let item = model.store.item(id: itemID) else { dismiss(); return }

        if item.title != title { item.title = title }
        if item.notes != notes { item.notes = notes }

        if isRichText, attributed.length > 0 {
            model.store.updateSnippet(item, attributed: attributed)
        } else if item.kind.isTextual {
            let current = model.store.resolveBodyText(item, key: model.vault.currentKey) ?? ""
            if current != body_ { model.store.updateSnippet(item, plain: body_) }
        }

        if item.tagNames != tags.sorted() { model.store.setTags(item, names: tags) }
        if item.folder?.id != folderID { model.fileItem(itemID, intoFolderID: folderID) }
        if item.isPinned != isPinned { model.togglePin(itemID) }

        item.updatedAt = Date()
        model.store.save()

        // Sealing is the one change that can fail — it needs the vault open — so it
        // goes last, through the model, which knows how to ask.
        if item.isSensitive != isSensitive { model.setItemSensitive(itemID, isSensitive) }

        model.store.refresh()
        model.runSearch()
        Theme.Haptics.success()
        dismiss()
    }
}
#endif
