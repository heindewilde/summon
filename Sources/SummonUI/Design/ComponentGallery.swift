import SwiftUI
import SummonKit

/// Every shared component, in every state, on one surface.
///
/// This exists because the token and component stages change the vocabulary without
/// adopting it anywhere — which makes them the two stages whose work is invisible in
/// a screenshot of the app. A gallery is the only way to review them before six
/// surfaces depend on them, and the only place the states of a row can be seen
/// side by side rather than one mouse position at a time.
public struct ComponentGallery: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                group("Row state") {
                    ForEach(Array(states.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: Theme.Space.s) {
                            KindIcon(kind: .text, style: .bare, size: 15)
                            Text(entry.name).font(Theme.Typography.title)
                            Spacer()
                            Text("⌘1").font(Theme.Typography.micro)
                                .foregroundStyle(Theme.faintText)
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .frame(width: 300, height: Theme.rowHeight)
                        .rowSurface(entry.state)
                    }
                }

                group("Kind icons") {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(ItemKind.allCases, id: \.self) { kind in
                            KindIcon(kind: kind, style: .bare, size: 15)
                        }
                    }
                    HStack(spacing: Theme.Space.s) {
                        ForEach(ItemKind.allCases, id: \.self) { kind in
                            KindIcon(kind: kind, style: .tile, size: 30)
                        }
                    }
                }

                group("Status") {
                    StatusBadge("Allowed")
                    StatusBadge("Needs attention", tone: .warning)
                    StatusBadge("Will delete", tone: .danger)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                group("Buttons") {
                    HStack(spacing: Theme.Space.s) {
                        Button("Start") {}.buttonStyle(.summonPrimary)
                        Button("Cancel") {}.buttonStyle(.summonQuiet)
                        Button("Delete") {}.buttonStyle(.summonDestructive)
                    }
                    Button("Disabled") {}.buttonStyle(.summonQuiet).disabled(true)
                }

                group("Fields") {
                    Text("Search this view")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 220, alignment: .leading)
                        .summonField()
                    Text("Focused")
                        .font(Theme.Typography.title)
                        .frame(width: 220, alignment: .leading)
                        .summonField(focused: true)
                }

                group("Keys") {
                    HStack(spacing: Theme.Space.s) {
                        KeyCap("⌥Space"); KeyCap("⌘K"); KeyCap("↩")
                    }
                }

                group("Cards") {
                    Text("A card, at rest")
                        .font(Theme.Typography.title)
                        .padding(Theme.Space.s)
                        .frame(width: 220, alignment: .leading)
                        .cardBackground(radius: Theme.Radius.large)
                    Text("Raised, with elevation")
                        .font(Theme.Typography.title)
                        .padding(Theme.Space.s)
                        .frame(width: 220, alignment: .leading)
                        .cardBackground(radius: Theme.Radius.large, raised: true)
                        .elevation(Theme.Elevation.popover)
                }

                group("Type") {
                    Text("Statement 25").font(Theme.Typography.statement)
                    Text("Display 21").font(Theme.Typography.display)
                    Text("Field 18").font(Theme.Typography.field)
                    Text("Heading 15").font(Theme.Typography.heading)
                    Text("Title 13").font(Theme.Typography.title)
                    Text("Body 12").font(Theme.Typography.body)
                    Text("Caption 11").font(Theme.Typography.caption)
                    Text("Micro 10").font(Theme.Typography.micro)
                }
            }
        }
        .foregroundStyle(Theme.primaryText)
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.chrome)
    }

    private var states: [(name: String, state: RowState)] {
        [("Idle", .idle), ("Hover", .hover), ("Selected", .selected),
         ("Selected, inactive pane", .selectedInactive),
         ("Nav active", .navActive), ("Drop target", .dropTarget)]
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title)
            content()
        }
    }
}
