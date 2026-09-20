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
/// Registers for the silent pushes CloudKit sends when another device changes the
/// library.
///
/// Without this, sync is one-way in practice: a device only discovers the other's
/// changes when it next launches, because NSPersistentCloudKitContainer is told to
/// fetch by a remote notification and nothing else. The app never shows a
/// notification — the payload is the signal, and the mirroring machinery handles it
/// once the app is registered.
final class PushRegistrar: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        Log.store.warning("Push registration failed, so sync will only catch up on launch: \(error.localizedDescription, privacy: .public)")
    }
}

@main
struct SummonPhoneApp: App {
    @UIApplicationDelegateAdaptor(PushRegistrar.self) private var pushRegistrar
    @Environment(\.scenePhase) private var scenePhase
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
                    let opened = try AppModel(services: .iOS())
                    opened.discardAbandonedBlanks()
                    model = opened
                } catch {
                    failure = error.localizedDescription
                }
            }
            // A push can be missed — the phone was off, or the notification was
            // dropped — so coming back to the app is its own cue to catch up.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let model else { return }
                model.store.refresh()
                model.runSearch()
            }
        }
    }
}
