// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// What this is, before the library has anything in it.
///
/// Three panes, skippable, shown once. A fresh install syncs nothing and seeds
/// nothing, so without this the first launch is an empty list and a search field —
/// which says neither what Summon holds nor how anything gets into it.
public struct WelcomeView: View {
    @Bindable var model: AppModel
    let finish: () -> Void

    public init(model: AppModel, finish: @escaping () -> Void) {
        self.model = model
        self.finish = finish
    }

    @State private var page = 0

    private struct Pane: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let panes = [
        Pane(symbol: "sparkles",
             title: "The things you keep reusing",
             body: """
             The reply you keep rewriting, the IBAN, the passport scan, the portfolio \
             PDF. Summon holds that handful — not everything — so it can be very good \
             at getting one of them to you.
             """),
        Pane(symbol: "hand.tap",
             title: "Tap to copy",
             body: """
             A tap puts an item on the clipboard, ready to paste wherever you were \
             going. The arrow beside it opens the item if you want to read or change \
             it first.
             """),
        Pane(symbol: "icloud",
             title: "Your Mac, in your pocket",
             body: """
             Everything syncs through your own iCloud — no account, no server of ours. \
             Items you mark sensitive are encrypted with a key Apple never sees.
             """),
    ]

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                    pane_(pane).tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: Theme.Space.m) {
                Button(page == panes.count - 1 ? "Get started" : "Next") {
                    if page == panes.count - 1 {
                        finish()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)

                Button("Skip") { finish() }
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.bottom, Theme.Space.xl)
        }
        .background(GlassBackground(material: .underWindowBackground, bloom: 0.9))
    }

    private func pane_(_ pane: Pane) -> some View {
        VStack(spacing: Theme.Space.l) {
            Spacer()
            Image(systemName: pane.symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(pane.title)
                .font(Theme.Typography.statement.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(pane.body)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            Spacer()
            Spacer()
        }
        .padding(Theme.Space.xl)
    }
}
#endif
