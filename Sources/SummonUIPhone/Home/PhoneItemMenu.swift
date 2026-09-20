// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// Everything you can do to an item, on a long press.
///
/// The Mac's `ItemContextMenu` with the Mac taken out: no "Reveal in Finder", and
/// "Open" means handing the file to another app rather than to the Finder. Delete goes
/// through the confirmation rather than straight to the store — a fingertip lands on a
/// menu item far more easily than a pointer does.
struct PhoneItemMenu: View {
    @Bindable var model: AppModel
    let item: ItemSnapshot
    let onOpenDetail: () -> Void

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { model.use(item.id, style: .copy) }
        Button("Open", systemImage: "chevron.right") { onOpenDetail() }
        Button(item.isPinned ? "Unpin" : "Pin",
               systemImage: item.isPinned ? "pin.slash" : "pin") { model.togglePin(item.id) }
        FolderPickerMenu(model: model, item: item)
        Divider()
        Button(item.isSensitive ? "Remove Sensitivity" : "Mark as Sensitive",
               systemImage: item.isSensitive ? "lock.open" : "lock") {
            model.setItemSensitive(item.id, !item.isSensitive)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.requestDelete(item.id)
        }
    }
}
#endif
