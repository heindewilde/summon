import AppKit
import SwiftUI

/// The panel's text field.
///
/// Deliberately an `NSTextField` rather than a SwiftUI `TextField`: a single-line
/// SwiftUI field swallows the arrow keys for caret movement, and arrow keys must
/// drive the result list. Wrapping AppKit is what makes the keyboard model work.
struct PanelSearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    var onMove: (Int) -> Void
    var onSubmit: (NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void
    var onTab: () -> Void
    var onDelete: () -> Void
    /// Change this value to pull focus back into the field.
    var focusToken: Int

    init(
        text: Binding<String>,
        placeholder: String = "Summon anything…",
        fontSize: CGFloat = 18,
        focusToken: Int = 0,
        onMove: @escaping (Int) -> Void = { _ in },
        onSubmit: @escaping (NSEvent.ModifierFlags) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        onTab: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.focusToken = focusToken
        self.onMove = onMove
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onTab = onTab
        self.onDelete = onDelete
    }

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
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
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
            let modifiers = NSApp.currentEvent?.modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []

            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1); return true
            case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
                parent.onMove(-8); return true
            case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
                parent.onMove(8); return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(modifiers); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                parent.onTab(); return true
            case #selector(NSResponder.deleteBackward(_:)):
                // Only intercept a delete on an already-empty field, so ⌫ still edits.
                if control.stringValue.isEmpty { parent.onDelete(); return true }
                return false
            default:
                return false
            }
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
    var onMove: (Int) -> Void
    var onSubmit: (NSEvent.ModifierFlags) -> Void
    var onCancel: () -> Void
    var onTab: () -> Void
    var onDelete: () -> Void

    @Environment(\.isSnapshotting) private var isSnapshotting

    public init(
        text: Binding<String>,
        placeholder: String = "Summon anything…",
        fontSize: CGFloat = 18,
        focusToken: Int = 0,
        onMove: @escaping (Int) -> Void = { _ in },
        onSubmit: @escaping (NSEvent.ModifierFlags) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        onTab: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.focusToken = focusToken
        self.onMove = onMove
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onTab = onTab
        self.onDelete = onDelete
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
                focusToken: focusToken, onMove: onMove, onSubmit: onSubmit,
                onCancel: onCancel, onTab: onTab, onDelete: onDelete
            )
        }
    }
}
