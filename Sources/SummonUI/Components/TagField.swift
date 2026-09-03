import AppKit
import SummonKit
import SwiftUI

/// Tags, as chips you can add and remove.
///
/// Replaces an `NSTokenField`, which was the native control but the wrong one here in
/// two ways. It drew the system's blue capsules, which are the loudest thing on
/// screen in an app that is otherwise entirely neutral. And it reported a change on
/// every keystroke, each of which wrote the tag list to the store — a save, a rebuild
/// of every snapshot in the library, and a re-index — so typing a five letter tag did
/// five full library refreshes. That was the lag.
///
/// This writes once, when a tag is actually added or removed.
public struct TagField: View {
    @Binding var tags: [String]

    /// Every tag already in the library. Matching ones are offered while you type, so
    /// near-duplicates — "invoice" and "invoices" — stop happening by accident.
    let suggestions: [String]
    /// How many items carry each tag, shown beside it in the menu.
    let counts: [String: Int]
    let onChange: ([String]) -> Void

    /// Pre-filled only by the screenshot harness, so the open menu can be reviewed.
    public var initialDraft: String?

    @State private var draft = ""
    @State private var contentHeight: CGFloat = 16
    /// Where the text field sits inside the well, so the menu opens under what is
    /// being typed rather than under the row.
    @State private var caretX: CGFloat = 0
    @State private var wellHeight: CGFloat = 26
    @State private var highlighted: Int?
    /// Set by Escape, cleared as soon as the draft changes: dismissing the menu
    /// should not also mean losing what you had typed.
    @State private var dismissed = false
    @FocusState private var focused: Bool

    public init(tags: Binding<[String]>, suggestions: [String],
                counts: [String: Int] = [:],
                initialDraft: String? = nil,
                onChange: @escaping ([String]) -> Void) {
        _tags = tags
        self.initialDraft = initialDraft
        self.suggestions = suggestions
        self.counts = counts
        self.onChange = onChange
    }

    public var body: some View {
        well
            .frame(maxWidth: .infinity, alignment: .leading)
            // Drawn over the rows below rather than pushed in above them: a list that
            // shoves Notes and Sensitive down every time you type a letter is the
            // thing that made this corner of the pane feel unsettled.
            .overlay(alignment: .topLeading) {
                if !matches.isEmpty {
                    dropdown
                        .offset(x: caretX, y: wellHeight + 2)
                        .zIndex(1)
                }
            }
    }

    /// A menu under what you are typing, driven by the arrow keys.
    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element) { index, name in
                Button { add(name) } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Text("#")
                            .foregroundStyle(Theme.tertiaryText)
                        Text(name)
                            .foregroundStyle(Theme.primaryText)
                        Spacer(minLength: Theme.Space.m)
                        // The count is the useful thing to know about an existing tag:
                        // it separates the one you have used forty times from a typo
                        // you made once.
                        if let uses = counts[name], uses > 0 {
                            Text("\(uses)")
                                .foregroundStyle(Theme.tertiaryText)
                                .monospacedDigit()
                        }
                    }
                    .font(Theme.Typography.meta)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(index == highlighted ? Theme.selection : .clear)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(Theme.Space.xxs)
        .frame(width: 200)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var well: some View {
        ScrollView(.vertical) {
            chips
                // Measured, so the well can be exactly as tall as its rows up to the
                // cap. A `maxHeight` alone does not do this: a flexible frame in a
                // form row takes the whole allowance, which left a well three lines
                // tall holding one line of tags.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(max(contentHeight, 16), 66))
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(focused ? Theme.primaryText.opacity(0.35) : Theme.hairline,
                              lineWidth: 1)
        )
        .contentShape(.rect)
        // Anywhere in the well puts the caret in the field, because the well is what
        // looks like the field.
        .onTapGesture { focused = true }
        .coordinateSpace(.named(Self.wellSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wellHeight = $0 }
        .onAppear { if let initialDraft { draft = initialDraft } }
    }

    private static let wellSpace = "summon.tagfield.well"

    private var chips: some View {
        FlowLayout(spacing: Theme.Space.xs, lineSpacing: Theme.Space.xs) {
            ForEach(tags, id: \.self) { tag in
                RemovableTagChip(name: tag) { remove(tag) }
            }
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.primaryText)
                .focused($focused)
                .frame(minWidth: 72)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .named(Self.wellSpace)).minX
                } action: { caretX = max(0, $0) }
                .onSubmit {
                    // Return takes the highlighted suggestion when the menu is open,
                    // and what you typed when it is not.
                    if let highlighted, matches.indices.contains(highlighted) {
                        add(matches[highlighted])
                    } else {
                        commit(draft)
                    }
                }
                .onKeyPress(.downArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    highlighted = min((highlighted ?? -1) + 1, matches.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !matches.isEmpty, let current = highlighted else { return .ignored }
                    // Stepping off the top closes the menu rather than wrapping to the
                    // bottom, so the arrow keys can hand focus back to what you typed.
                    highlighted = current == 0 ? nil : current - 1
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !matches.isEmpty else { return .ignored }
                    dismissed = true
                    return .handled
                }
                // A comma ends a tag, the habit the old comma-separated field trained.
                // Handled on change rather than as a key press so pasting "a, b, c"
                // becomes three tags too.
                .onChange(of: draft) { _, new in
                    dismissed = false
                    highlighted = nil
                    guard new.contains(",") else { return }
                    let parts = new.split(separator: ",", omittingEmptySubsequences: false)
                    for part in parts.dropLast() { add(String(part)) }
                    draft = String(parts.last ?? "")
                }
                .onKeyPress(.delete) {
                    // Backspace on an empty field eats the tag before the caret, which
                    // is what every chip field does and what the fingers expect.
                    guard draft.isEmpty, let last = tags.last else { return .ignored }
                    remove(last)
                    return .handled
                }
                .onKeyPress(.tab) {
                    // Completes to the best match rather than moving focus, while
                    // there is a match to complete to.
                    guard let first = matches.first else { return .ignored }
                    add(first)
                    return .handled
                }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Tags you already have that start with what is being typed. Offered rather than
    /// autocompleted, so typing a genuinely new tag is never fought.
    private var matches: [String] {
        // Keyed on the draft, not on focus. Clicking a suggestion moves focus out of
        // the text field on mouse-*down*, so a focus-gated row would delete itself
        // out from under the pointer and the click would land on nothing.
        let typed = draft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty, !dismissed else { return [] }
        let taken = Set(tags)
        return suggestions
            .filter { $0.hasPrefix(typed) && !taken.contains($0) && $0 != typed }
            .prefix(4)
            .map { $0 }
    }

    // MARK: - Editing

    private func commit(_ text: String) {
        add(text)
        draft = ""
    }

    private func add(_ raw: String) {
        // Normalised the same way the store normalises, so "Invoice" and "invoice "
        // cannot become two tags that look identical in the sidebar.
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, !tags.contains(name) else {
            draft = ""
            return
        }
        tags.append(name)
        draft = ""
        onChange(tags)
    }

    private func remove(_ name: String) {
        guard let index = tags.firstIndex(of: name) else { return }
        tags.remove(at: index)
        onChange(tags)
    }
}

/// A `TagChip` you can take off.
///
/// Deliberately the same capsule the panel and the sidebar already draw — same "#",
/// same size, same neutral fill — with a remove button added. A second tag look for
/// the one place tags are editable would be a third dialect in an app that has been
/// careful to speak one.
private struct RemovableTagChip: View {
    let name: String
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            Text("#\(name)")
                .font(Theme.Typography.micro.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
            // Only the cross removes it — a chip that deletes itself on any click is
            // one slip away from losing a tag you meant to read. The hit area is
            // bigger than the glyph so it is still an easy target.
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(hovering ? Theme.primaryText : Theme.tertiaryText)
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Remove \u{201C}\(name)\u{201D}")
            .accessibilityLabel("Remove the tag \(name)")
        }
        .padding(.leading, Theme.Space.xs)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        // Hover, so the neutral hover fill. `Theme.selection` here meant a tag chip lit
        // up in the accent whenever the pointer crossed it.
        .background(hovering ? Theme.rowHover : Theme.hairline, in: .capsule)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tag \(name)")
    }
}
