// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import PhotosUI
import SummonKit
import SummonUI
import SwiftUI
import UniformTypeIdentifiers

/// Getting things in, on a phone.
///
/// The Mac has four ways in — drag, the Services menu, the save hot key, the import
/// panel — and a phone has none of them. This is the replacement: one button whose
/// menu covers the same ground, plus the share sheet once that extension exists.
public struct AddMenu: View {
    @Bindable var model: AppModel

    @State private var choosingFiles = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var busy = false

    /// Where a file chosen from here is filed. The sidebar's "Add Files…" and the
    /// empty state both ask for a folder; the toolbar button does not.
    @State private var destination: SummonFolder?

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Menu {
            Button("New Snippet", systemImage: "square.and.pencil") { model.beginNewSnippet() }
            Button("Save What I Copied", systemImage: "doc.on.clipboard") {
                Task { await saveClipboard() }
            }
            Divider()
            Button("Choose Files…", systemImage: "folder") { choosingFiles = true }
            // A `PhotosPicker` placed inside a `Menu` renders but never presents: the
            // menu dismisses itself before the picker it was holding can appear. The
            // button sets a flag and the modifier below does the presenting.
            Button("Choose a Photo…", systemImage: "photo") { choosingPhoto = true }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(busy)
        .fileImporter(isPresented: $choosingFiles,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importPickedFiles(urls, into: destination)
            case .failure(let error):
                model.show(Toast(text: "Couldn’t open that", symbol: "exclamationmark.triangle",
                                 tone: .danger, detail: error.localizedDescription))
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        // Every other way into the importer — the folder menu, an empty state —
        // routes here, so a phone has one file picker rather than several that
        // disagree. `presentImportPanel` was an empty function on iOS before this.
        .onAppear {
            model.presentImportHandler = { folder in
                destination = folder
                choosingFiles = true
            }
        }
        .onChange(of: photo) { _, picked in
            guard let picked else { return }
            Task { await savePhoto(picked) }
        }
    }

    /// The honest analogue of the Mac's clipboard history: a phone cannot watch the
    /// pasteboard in the background, so it asks only when you say to — which is also
    /// the only way to read it without a permission banner on every launch.
    private func saveClipboard() async {
        busy = true
        defer { busy = false }
        await model.saveClipboard()
    }

    private func savePhoto(_ picked: PhotosPickerItem) async {
        busy = true
        defer { busy = false; photo = nil; destination = nil }
        guard let data = try? await picked.loadTransferable(type: Data.self) else {
            model.show(Toast(text: "Couldn’t read that photo", symbol: "photo", tone: .danger))
            return
        }
        await model.importImageData(data)
    }
}
#endif
