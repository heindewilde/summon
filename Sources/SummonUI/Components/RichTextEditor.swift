import AppKit
import SwiftUI
import SummonKit

/// An `NSTextView`-backed editor that preserves formatting.
///
/// SwiftUI's `TextEditor` is plain-text only, so editing a snippet copied out of Mail
/// through it would throw the formatting away. Canned replies are exactly the content
/// where that matters, so rich snippets get a real text view.
public struct RichTextEditor: NSViewRepresentable {
    @Binding public var attributed: NSAttributedString
    public var isEditable: Bool
    public var fontSize: CGFloat

    public init(attributed: Binding<NSAttributedString>, isEditable: Bool = true, fontSize: CGFloat = 12.5) {
        _attributed = attributed
        self.isEditable = isEditable
        self.fontSize = fontSize
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.font = .systemFont(ofSize: fontSize)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        // Content pasted from a light-background app carries explicit black text.
        // Without this it is unreadable in dark mode.
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.textStorage?.setAttributedString(attributed)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        // Only replace the contents when the model genuinely differs, or every
        // keystroke would reset the selection to the start of the document.
        if !context.coordinator.isEditing,
           textView.attributedString() != attributed {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributed)
            if selection.location <= textView.string.utf16.count {
                textView.setSelectedRange(selection)
            }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isEditing = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        public func textDidBeginEditing(_ notification: Notification) { isEditing = true }
        public func textDidEndEditing(_ notification: Notification) { isEditing = false }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributed = textView.attributedString()
        }
    }
}

/// Rich editor in normal use; a static rendering while snapshotting, since
/// `ImageRenderer` cannot draw an `NSViewRepresentable`.
public struct SnippetEditor: View {
    @Binding public var attributed: NSAttributedString
    public var isEditable: Bool
    @Environment(\.isSnapshotting) private var isSnapshotting

    public init(attributed: Binding<NSAttributedString>, isEditable: Bool = true) {
        _attributed = attributed
        self.isEditable = isEditable
    }

    public var body: some View {
        if isSnapshotting {
            PlaceholderHighlightedText(text: attributed.string)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.xs)
        } else {
            RichTextEditor(attributed: $attributed, isEditable: isEditable)
        }
    }
}
