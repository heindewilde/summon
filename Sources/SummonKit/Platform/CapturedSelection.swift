import Foundation

/// What the save-selection gesture managed to grab.
///
/// Portable by nature — URLs, a string, some bytes — though it lived in
/// `SelectionCapture.swift` next to the Apple Events and the synthesised ⌘C that
/// produce it on a Mac. The importer consumes this and does not care how it was got.
/// What the save-selection hotkey managed to grab.
public enum CapturedSelection: Sendable {
    case files([URL])
    case text(String, rtf: Data?)
    case image(Data)
    case nothing
}
