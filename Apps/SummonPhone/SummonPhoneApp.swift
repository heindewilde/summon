import SummonKit
import SummonUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The iOS companion.
///
/// Deliberately thin. Everything it draws — the sidebar, the list, the detail pane,
/// the design system — is the same code the Mac draws, and everything it knows how to
/// do comes from `PlatformServices.iOS()`. If this file grows much, something that
/// should have been shared has been rewritten instead.
@main
struct SummonPhoneApp: App {
    @State private var model: AppModel?
    @State private var failure: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let model {
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        PhoneRootView(model: model)
                    } else {
                        MainWindowView(model: model)
                    }
                    #else
                    MainWindowView(model: model)
                    #endif
                } else if let failure {
                    // The same posture the Mac takes: a library that will not open is
                    // said out loud rather than logged and shrugged at.
                    ContentUnavailableView("Summon couldn't open your library",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    ProgressView()
                }
            }
            .task {
                guard model == nil, failure == nil else { return }
                do {
                    model = try AppModel(services: .iOS())
                } catch {
                    failure = error.localizedDescription
                }
            }
        }
    }
}
