import AppKit
import SummonKit
import SummonUI
import SummonUIMac
import SummonKitMac

/// Single construction point for the app's services.
///
/// A lazy `static let` on the main actor, so both the SwiftUI scenes and the AppKit
/// delegate observe exactly one `AppModel` without either having to own it.
@MainActor
enum Services {
    static let model: AppModel = {
        do {
            return try AppModel(services: .macOS())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Summon couldn’t open your library"
            alert.informativeText = """
            \(error.localizedDescription)

            The library lives in ~/Library/Application Support/Summon. \
            Moving that folder aside will let Summon start with a fresh one.
            """
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            exit(1)
        }
    }()
}
