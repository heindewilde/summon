import AppKit
import SwiftUI

/// The panel's text field.
///
/// Deliberately an `NSTextField` rather than a SwiftUI `TextField`: a single-line
/// SwiftUI field swallows the arrow keys for caret movement, and arrow keys must
/// drive the result list. Wrapping AppKit is what makes the keyboard model work.
///
/// It takes exactly one behaviour closure. The six it used to take were a second copy
/// of the keyboard model living next to the real one — the way a footer hint and its
/// binding drift apart. Everything now resolves through `PanelKeyMap`.
struct PanelSearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    /// Returns true when the panel claimed the key, false to let the field have it.
    var route: (Selector, Bool) -> Bool
    /// Change this value to pull focus back into the field.
    var focusToken: Int

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize, weight: .regular)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // Without this VoiceOver announces an unnamed text field — for the one
        // control the whole app is built around.
        field.setAccessibilityLabel("Search your library")
        field.setAccessibilityHelp("Type to search. Up and down arrows move through results, Return inserts, ⌘K opens actions.")
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Guarded: writing into a field that already holds this text would disturb an
        // active field editor mid-edit.
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: fontSize, weight: .regular)

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
            }
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchFieldRepresentable
        var lastFocusToken: Int

        init(_ parent: PanelSearchFieldRepresentable) {
            self.parent = parent
            self.lastFocusToken = parent.focusToken
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            parent.route(selector, textView.string.isEmpty)
        }
    }
}

/// Public wrapper: the AppKit field in normal use, a static rendering while
/// snapshotting for design review.
public struct PanelSearchField: View {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var focusToken: Int
    var route: (Selector, Bool) -> Bool

    @Environment(\.isSnapshotting) private var isSnapshotting

    public init(
        text: Binding<String>,
        placeholder: String = "Summon anything…",
        fontSize: CGFloat = 18,
        focusToken: Int = 0,
        route: @escaping (Selector, Bool) -> Bool = { _, _ in false }
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.focusToken = focusToken
        self.route = route
    }

    public var body: some View {
        if isSnapshotting {
            HStack(spacing: 1) {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(text.isEmpty ? Theme.tertiaryText : Theme.primaryText)
                    .lineLimit(1)
                if !text.isEmpty {
                    Rectangle().fill(Theme.primaryText).frame(width: 1.5, height: fontSize * 1.1)
                }
                Spacer(minLength: 0)
            }
        } else {
            PanelSearchFieldRepresentable(
                text: $text, placeholder: placeholder, fontSize: fontSize,
                route: route, focusToken: focusToken
            )
        }
    }
}
