import AppKit
import SwiftUI
import SummonKit

/// Click, then press the combination you want. Escape cancels, Delete clears.
public struct HotKeyRecorder: View {
    @Binding public var combo: HotKeyCombo
    public var onChange: (HotKeyCombo) -> Void

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    public init(combo: Binding<HotKeyCombo>, onChange: @escaping (HotKeyCombo) -> Void = { _ in }) {
        _combo = combo
        self.onChange = onChange
    }

    public var body: some View {
        Button {
            recording.toggle()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: recording ? "record.circle" : "keyboard")
                    .font(Theme.Icon.small)
                    .foregroundStyle(recording ? Theme.danger : Theme.secondaryText)
                Text(recording ? "Press keys…" : combo.displayString)
                    .font(.system(size: 12, weight: .medium, design: recording ? .default : .rounded))
                    .monospacedDigit()
            }
            .frame(minWidth: 116)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 5)
            .background(
                recording ? Theme.danger.opacity(0.10) : (hovering ? Theme.rowHover : Theme.surface),
                in: .rect(cornerRadius: Theme.Radius.small)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small)
                    .strokeBorder(recording ? Theme.danger.opacity(0.5) : Theme.hairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onChange(of: recording) { _, isRecording in
            isRecording ? startRecording() : stopRecording()
        }
        .onDisappear(perform: stopRecording)
        .accessibilityLabel("Keyboard shortcut, currently \(combo.displayString)")
        .accessibilityHint("Activate, then press the shortcut you want")
    }

    private func startRecording() {
        stopRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels without changing anything
                recording = false
                return nil
            }
            guard let candidate = HotKeyCombo(event: event) else {
                // A bare key would fire while typing anywhere; require a modifier.
                NSSound.beep()
                return nil
            }
            combo = candidate
            onChange(candidate)
            recording = false
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
