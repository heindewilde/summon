// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// The step between choosing a snippet and using it: fill in what varies.
///
/// The Mac asks this inside the summon panel. A phone has no panel, and until now it
/// had no answer at all: `AppModel.use()` entered `.fill` mode, nothing was listening,
/// and tapping a snippet with `{{first_name}}` in it appeared to do nothing whatsoever.
struct FillFieldsSheet: View {
    @Bindable var model: AppModel
    let itemID: UUID
    let dismiss: () -> Void

    @State private var template: SnippetTemplate?
    @FocusState private var focused: String?

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(template?.fields ?? [], id: \.name) { field in
                        LabeledContent(field.label) {
                            TextField(field.defaultValue ?? "", text: Binding(
                                get: { model.fieldValues[field.name] ?? "" },
                                set: { model.fieldValues[field.name] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .focused($focused, equals: field.name)
                            .submitLabel(isLast(field) ? .done : .next)
                            .onSubmit { advance(from: field) }
                        }
                    }
                } footer: {
                    Text("Dates, times and the clipboard fill themselves in.")
                }

                // The result, as it will be copied. A form of blanks says nothing
                // about what you are about to paste; this does.
                Section("Preview") {
                    Text(preview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle(snapshot?.title ?? "Fill in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.dismissPanel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { complete() }
                }
            }
            .onAppear {
                template = model.store.template(for: itemID)
                focused = template?.fields.first?.name
            }
        }
    }

    private var preview: String {
        model.store.payload(for: itemID, fieldValues: model.fieldValues,
                            clipboard: model.inserter.currentClipboardText())?.plainText ?? ""
    }

    private func isLast(_ field: SnippetField) -> Bool {
        template?.fields.last?.name == field.name
    }

    private func advance(from field: SnippetField) {
        guard let fields = template?.fields,
              let index = fields.firstIndex(where: { $0.name == field.name }),
              index + 1 < fields.count
        else {
            complete()
            return
        }
        focused = fields[index + 1].name
    }

    private func complete() {
        model.completeFill(for: itemID, style: .copy)
        dismiss()
    }
}
#endif
