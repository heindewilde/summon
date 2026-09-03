import AppKit
import SwiftUI
import SummonKit

/// The step between choosing a snippet and inserting it: fill in what varies.
///
/// This is what turns a canned reply into a real one, and it is the direct answer to
/// "information used to fill out forms".
public struct FillFieldsPane: View {
    @Bindable var model: AppModel
    let itemID: UUID

    @FocusState private var focusedField: String?
    @State private var template: SnippetTemplate?

    public init(model: AppModel, itemID: UUID) {
        self.model = model
        self.itemID = itemID
    }

    private var snapshot: ItemSnapshot? {
        model.store.snapshots.first { $0.id == itemID }
    }

    public var body: some View {
        HStack(spacing: 0) {
            fields
                .frame(width: PanelView.width * 0.55)
            Rule()
            preview
        }
        .onAppear(perform: load)
    }

    private var fields: some View {
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "square.dashed.inset.filled")
                        .foregroundStyle(Theme.primaryText)
                    Text(snapshot?.title ?? "Fill in")
                        .font(Theme.Typography.title.weight(.semibold))
                }

                ForEach(template?.fields ?? [], id: \.name) { field in
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(field.label)
                            .font(Theme.Typography.micro.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                        TextField(
                            field.defaultValue ?? "",
                            text: Binding(
                                get: { model.fieldValues[field.name] ?? "" },
                                set: { model.fieldValues[field.name] = $0 }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.title)
                        .summonField(focused: focusedField == field.name)
                        .focused($focusedField, equals: field.name)
                        .onSubmit(insert)
                    }
                }

                HStack(spacing: Theme.Space.xs) {
                    // Were `.borderedProminent` tinted with `primaryText` and `.bordered`
                    // — AppKit's capsules, with AppKit's hover chrome, sitting inside a
                    // panel that draws everything else itself. The tint was a workaround
                    // for the system accent being the only saturated colour available;
                    // the app has its own now.
                    Button("Insert", action: insert)
                        .buttonStyle(.summonPrimary)
                        .keyboardShortcut(.defaultAction)
                    Button("Back") { model.mode = .search }
                        .buttonStyle(.summonQuiet)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, Theme.Space.xxs)
            }
            .padding(Theme.Space.m)
        }
    }

    private var preview: some View {
        SnapshotSafeScrollView {
            Text(rendered)
                .font(Theme.Typography.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m)
        }
        .overlay(alignment: .topTrailing) {
            SectionHeader("Preview")
                .padding(Theme.Space.xs)
        }
    }

    /// Live preview, so you can see the finished text before it lands anywhere.
    private var rendered: String {
        guard let template else { return "" }
        return template.render(
            values: model.fieldValues,
            context: RenderContext(clipboard: model.inserter.currentClipboardText())
        ).text
    }

    private func load() {
        template = model.store.template(for: itemID)
        focusedField = template?.fields.first?.name
    }

    private func insert() {
        model.completeFill(for: itemID, style: .paste)
    }
}
