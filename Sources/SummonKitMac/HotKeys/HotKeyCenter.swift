import AppKit
import Carbon.HIToolbox
import Foundation
import SummonKit

/// System-wide shortcuts via Carbon's `RegisterEventHotKey`.
///
/// Deliberately not `NSEvent.addGlobalMonitorForEvents` or a `CGEventTap`: those
/// require the Accessibility permission, and the app should be summonable the moment
/// it is installed. The only thing Accessibility is ever used for here is the paste
/// keystroke itself, which has a working fallback.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public enum Slot: UInt32, CaseIterable {
        case summon = 1
        case quickSave = 2
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x534D_4E00 // 'SMN\0'

    private init() {}

    /// Registers a shortcut. Returns false when another app already owns it, which
    /// is the signal for onboarding to offer an alternative rather than fail silently.
    @discardableResult
    public func register(_ slot: Slot, combo: HotKeyCombo, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()
        unregister(slot)

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: slot.rawValue)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.app.warning("Hot key \(combo.displayString, privacy: .public) is unavailable (status \(status)).")
            return false
        }
        refs[slot.rawValue] = ref
        handlers[slot.rawValue] = handler
        return true
    }

    public func unregister(_ slot: Slot) {
        if let ref = refs.removeValue(forKey: slot.rawValue) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: slot.rawValue)
    }

    public func unregisterAll() {
        for slot in Slot.allCases { unregister(slot) }
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), summonHotKeyHandler, 1, &spec, nil, &eventHandler)
    }
}

/// Carbon requires a bare C function pointer. Hot key events are delivered on the
/// main run loop, which is what makes `assumeIsolated` correct here.
private func summonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }

    MainActor.assumeIsolated {
        HotKeyCenter.shared.fire(id: hotKeyID.id)
    }
    return noErr
}
