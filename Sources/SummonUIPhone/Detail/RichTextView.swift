// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI
import UIKit

/// The iOS twin of the Mac's `RichTextEditor`.
///
/// A rich snippet keeps its bold, its links and its lists, and until now the phone
/// could only look at one: `SnippetEditor` is built on `NSTextView`, so iOS fell back
/// to static text and a rich item was the one thing in the library you could not edit
/// where you stood.
///
/// `UITextView` does the same job with the same `NSAttributedString`, which is what
/// `RTF.swift` already reads and writes for both platforms — so what is typed here
/// arrives on the Mac as itself, bold and all.
struct RichTextView: UIViewRepresentable {
    @Binding var text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.allowsEditingTextAttributes = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        // Typing attributes rather than a font on the view: a font set on the view is
        // applied to everything, which would flatten the formatting this exists to keep.
        view.typingAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // Only when it actually differs. Assigning on every pass resets the selection,
        // so the caret jumped to the end after each keystroke.
        guard view.attributedText != text else { return }
        let selection = view.selectedRange
        view.attributedText = text
        view.selectedRange = selection
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<NSAttributedString>

        init(text: Binding<NSAttributedString>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.attributedText
        }
    }
}
#endif
