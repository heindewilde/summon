import AppKit
import SwiftUI
import SummonKit

/// Four boxes that fill as you type.
///
/// A real `TextField` underneath, made invisible, with the boxes drawn from its
/// value. Everything a text field already knows how to do — the caret, backspace,
/// select-all, holding a key down, ⌘V, VoiceOver — keeps working, which is not true
/// of four separate fields wired together by hand.
public struct PINField: View {
    @Binding var digits: String
    let isError: Bool
    let onComplete: () -> Void

    @FocusState private var focused: Bool
    /// Bumped to re-run the entry animation on the box that just filled.
    @State private var landed: Int?

    public init(digits: Binding<String>, isError: Bool = false,
                onComplete: @escaping () -> Void = {}) {
        _digits = digits
        self.isError = isError
        self.onComplete = onComplete
    }

    private var length: Int { PINPolicy.length }

    public var body: some View {
        ZStack {
            // The field itself carries the text and the keyboard; it is never seen.
            // Sized rather than hidden: a zero-size or `.hidden()` field cannot take
            // first responder, so the boxes would have nothing feeding them.
            TextField("", text: $digits)
                .textFieldStyle(.plain)
                .textContentType(nil)
                .focused($focused)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .onChange(of: digits) { old, new in
                    let cleaned = String(new.filter(\.isNumber).prefix(length))
                    if cleaned != new { digits = cleaned; return }
                    if cleaned.count > old.count { landed = cleaned.count - 1 }
                    if cleaned.count == length { onComplete() }
                }

            HStack(spacing: Theme.Space.s) {
                ForEach(0..<length, id: \.self) { index in
                    box(index)
                }
            }
            .contentShape(.rect)
            // Anywhere on the boxes puts the caret back, because the thing that looks
            // like the field is the boxes.
            .onTapGesture { focused = true }
        }
        .onAppear {
            // A beat first. A sheet is not in the responder chain on its very first
            // pass, so focusing immediately is silently dropped and the digits you
            // type straight away go nowhere at all.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                focused = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN, \(length) digits")
        .accessibilityValue("\(digits.count) of \(length) entered")
        .accessibilityAddTraits(.isSearchField)
    }

    private func box(_ index: Int) -> some View {
        let isFilled = index < digits.count
        // The caret sits on the next empty box, so it is obvious where typing lands.
        let isNext = index == digits.count && focused

        return RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(Theme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(borderColor(isNext: isNext), lineWidth: isNext ? 1.5 : 1)
            }
            .overlay {
                Circle()
                    .fill(isError ? Theme.danger : Theme.primaryText)
                    .frame(width: 9, height: 9)
                    .opacity(isFilled ? 1 : 0)
                    .scaleEffect(landed == index ? 1 : (isFilled ? 1 : 0.4))
            }
            .frame(width: 44, height: 52)
            .animation(.spring(duration: 0.22), value: isFilled)
    }

    private func borderColor(isNext: Bool) -> Color {
        if isError { return Theme.danger }
        return isNext ? Theme.primaryText.opacity(0.5) : Theme.hairline
    }
}
