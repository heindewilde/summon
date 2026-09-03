import SwiftUI

// Settings' own vocabulary.
//
// This screen was a stock `Form(.grouped)` in a stock `TabView`, which is the single
// clearest tell that an app's chrome was borrowed: it reads as System Settings with
// someone else's rows in it. `Form` is a good default and the wrong one here, because
// every other surface in this app draws its own cards on its own ground, and Settings
// was the one place that opted out.

/// One settings tab: sections on the app's ground.
public struct SettingsPage<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        // Snapshot-safe: `ImageRenderer` proposes unbounded height to a `ScrollView`,
        // which collapses its content to nothing — the settings page rendered as an
        // empty ground the first time this was captured.
        SnapshotSafeScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                content
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(GlassBackground(material: .underWindowBackground, bloom: 0.55))
        // Every control on the page inherits the app's accent instead of the system's.
        .tint(Theme.accent)
    }
}

/// A titled group of rows, as one card.
public struct SettingsSection<Content: View>: View {
    private let title: String
    private let content: Content
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                content
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground(radius: Theme.Radius.large)
        }
    }
}

/// A label with a control or a value opposite it. Stands in for `LabeledContent`,
/// whose whole purpose is to inherit `Form`'s label column — which is exactly the
/// thing being replaced.
public struct SettingsRow<Control: View>: View {
    private let label: String
    private let control: Control

    public init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(label)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: Theme.Space.s)
            control
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension SettingsRow where Control == Text {
    init(_ label: String, value: String) {
        self.init(label) {
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// The tab rail. A `TabView`'s macOS chrome is the other half of the System Settings
/// look, and it cannot be restyled.
public struct SettingsTabRail<Tab: Hashable>: View {
    private let tabs: [(tab: Tab, title: String, symbol: String)]
    @Binding private var selection: Tab

    public init(selection: Binding<Tab>, tabs: [(tab: Tab, title: String, symbol: String)]) {
        _selection = selection
        self.tabs = tabs
    }

    public var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, entry in
                let isOn = entry.tab == selection
                Button { selection = entry.tab } label: {
                    VStack(spacing: Theme.Space.xxs) {
                        Image(systemName: entry.symbol)
                            .font(Theme.Icon.large)
                            .glow(isOn ? Theme.accent : .clear, radius: 6, strength: 0.8)
                        Text(entry.title).font(Theme.Typography.caption)
                    }
                    .foregroundStyle(isOn ? Theme.primaryText : Theme.secondaryText)
                    .frame(width: 76)
                    .padding(.vertical, Theme.Space.s)
                    .rowSurface(isOn ? .selected : .idle, radius: Theme.Radius.medium)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(GlassBackground(material: .headerView, bloom: 0.9))
        .overlay(alignment: .bottom) { Rule() }
    }
}
