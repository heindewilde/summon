// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// The questions the app can ask from anywhere: fill in these blanks, confirm this
/// deletion, set or prove your PIN.
///
/// Collected in one modifier because a view can only present one sheet at a time, and
/// scattering them meant whichever screen happened to be on top swallowed the rest —
/// which is exactly how "Set a PIN" came to do nothing at all.
struct PhoneSheets: ViewModifier {
    @Bindable var model: AppModel

    private struct FillTarget: Identifiable { let id: UUID }

    private var fillTarget: FillTarget? {
        if case .fill(let id) = model.mode { FillTarget(id: id) } else { nil }
    }

    /// True while something is waiting on the vault. The model sets this when a locked
    /// item is chosen; on the Mac the panel answers it, and on a phone nothing did —
    /// tapping a locked item appeared to do nothing at all unless Face ID happened to
    /// be enrolled and succeeded on its own.
    private var isUnlocking: Bool {
        if case .unlock = model.mode { true } else { false }
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { isUnlocking },
                                        set: { if !$0 { model.dismissPanel() } })) {
                // Dismisses itself: a successful unlock puts the model back in search
                // mode and then does the thing that was waiting.
                VaultSheet(model: model) { model.dismissPanel() }
            }
            .sheet(item: Binding(get: { fillTarget },
                                 set: { if $0 == nil { model.dismissPanel() } })) { target in
                FillFieldsSheet(model: model, itemID: target.id) { model.dismissPanel() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: Binding(get: { model.lockSheet },
                                 set: { if $0 == nil { model.cancelLockSheet() } })) { purpose in
                LockSheet(model: model, purpose: purpose) { model.finishLockSheet() }
            }
            .alert("Delete “\(model.pendingDeleteTitle)”?",
                   isPresented: Binding(get: { model.pendingDeleteID != nil },
                                        set: { if !$0 { model.pendingDeleteID = nil } })) {
                Button("Delete", role: .destructive) {
                    model.confirmPendingDelete()
                    Theme.Haptics.warning()
                }
                Button("Cancel", role: .cancel) { model.pendingDeleteID = nil }
            } message: {
                Text("This cannot be undone.")
            }
    }
}

extension View {
    func phoneSheets(model: AppModel) -> some View { modifier(PhoneSheets(model: model)) }
}
#endif
