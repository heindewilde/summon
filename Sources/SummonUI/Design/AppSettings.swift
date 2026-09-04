import Foundation
import Observation
import SummonKit

/// Which appearance the app draws in, regardless of the system's.
///
/// Every colour in `Theme` is already defined for both appearances, so this only has
/// to tell AppKit which one to resolve against.
public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

}

/// User preferences, persisted in UserDefaults. Small enough to keep in one place.
@MainActor
@Observable
public final class AppSettings {
    private let defaults = UserDefaults.standard

    public var quickSaveEnabled: Bool {
        didSet { defaults.set(quickSaveEnabled, forKey: "hotkey.quickSave.enabled") }
    }

    public var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: "clipboard.enabled") }
    }
    public var clipboardPersists: Bool {
        didSet { defaults.set(clipboardPersists, forKey: "clipboard.persist") }
    }
    public var clipboardLimit: Int {
        didSet { defaults.set(clipboardLimit, forKey: "clipboard.limit") }
    }

    public var autoLockMinutes: Int {
        didSet { defaults.set(autoLockMinutes, forKey: "vault.autoLockMinutes") }
    }
    public var intelligenceEnabled: Bool {
        didSet { defaults.set(intelligenceEnabled, forKey: "intelligence.enabled") }
    }
    public var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: "app.showDockIcon") }
    }
    public var appearance: AppearanceChoice {
        didSet {
            defaults.set(appearance.rawValue, forKey: "app.appearance")
            applyAppearance()
        }
    }
    public var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: "insert.autoPaste") }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "app.onboarded") }
    }

    public init() {
        defaults.register(defaults: [
            "clipboard.enabled": true,
            "clipboard.persist": false,
            "clipboard.limit": 40,
            "vault.autoLockMinutes": 5,
            "intelligence.enabled": true,
            "app.showDockIcon": true,
            "insert.autoPaste": true,
            "app.onboarded": false,
            "hotkey.quickSave.enabled": true,
            "app.appearance": AppearanceChoice.system.rawValue,
        ])

        quickSaveEnabled = defaults.bool(forKey: "hotkey.quickSave.enabled")
        clipboardHistoryEnabled = defaults.bool(forKey: "clipboard.enabled")
        clipboardPersists = defaults.bool(forKey: "clipboard.persist")
        clipboardLimit = defaults.integer(forKey: "clipboard.limit")
        autoLockMinutes = defaults.integer(forKey: "vault.autoLockMinutes")
        intelligenceEnabled = defaults.bool(forKey: "intelligence.enabled")
        showDockIcon = defaults.bool(forKey: "app.showDockIcon")
        autoPaste = defaults.bool(forKey: "insert.autoPaste")
        hasCompletedOnboarding = defaults.bool(forKey: "app.onboarded")
        appearance = AppearanceChoice(rawValue: defaults.string(forKey: "app.appearance") ?? "")
            ?? .system
        applyAppearance()
    }

    /// Applies the chosen appearance. Set by whichever platform is running.
    ///
    /// This used to be `NSApp?.appearance = ...` inline, which is a single line and a
    /// whole-target dependency: it is the only reason these preferences needed AppKit.
    /// Applied app-wide rather than to a view tree because the panel is its own
    /// window, and a `.preferredColorScheme` on the library's view would leave it
    /// still drawing in the system's appearance.
    @ObservationIgnored public var appearanceDidChange: ((AppearanceChoice) -> Void)?

    public func applyAppearance() {
        appearanceDidChange?(appearance)
    }
}
