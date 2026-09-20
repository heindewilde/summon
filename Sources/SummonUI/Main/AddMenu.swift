#if !canImport(AppKit)
import PhotosUI
import SummonKit
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
    @State private var photo: PhotosPickerItem?
    @State private var busy = false

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Menu {
            Button("New Snippet", systemImage: "square.and.pencil") { model.beginNewSnippet() }
            Button("Save What I Copied", systemImage: "doc.on.clipboard") {
                Task { await saveClipboard() }
            }
            Divider()
            Button("Choose Files…", systemImage: "folder") { choosingFiles = true }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Choose a Photo…", systemImage: "photo")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(busy)
        .fileImporter(isPresented: $choosingFiles,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importPickedFiles(urls)
            case .failure(let error):
                model.show(Toast(text: "Couldn’t open that", symbol: "exclamationmark.triangle",
                                 tone: .danger, detail: error.localizedDescription))
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
        defer { busy = false; photo = nil }
        guard let data = try? await picked.loadTransferable(type: Data.self) else {
            model.show(Toast(text: "Couldn’t read that photo", symbol: "photo", tone: .danger))
            return
        }
        await model.importImageData(data)
    }
}
#endif
