import AppKit
import Foundation
import Observation
import ServiceManagement
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

    /// Nil means "follow the system", which is what a nil `NSApp.appearance` does.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences, persisted in UserDefaults. Small enough to keep in one place.
@MainActor
@Observable
public final class AppSettings {
    private let defaults = UserDefaults.standard

    public var summonHotKey: HotKeyCombo {
        didSet { store(summonHotKey, "hotkey.summon") }
    }
    public var quickSaveHotKey: HotKeyCombo {
        didSet { store(quickSaveHotKey, "hotkey.quickSave") }
    }
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

        summonHotKey = AppSettings.load("hotkey.summon") ?? .defaultSummon
        quickSaveHotKey = AppSettings.load("hotkey.quickSave") ?? .defaultQuickSave
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

    /// Applied to the whole app rather than to a view tree: the panel is its own
    /// window, and a `.preferredColorScheme` on the library's view would leave it
    /// still drawing in the system's appearance.
    public func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    private func store(_ combo: HotKeyCombo, _ key: String) {
        guard let data = try? JSONEncoder().encode(combo) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(_ key: String) -> HotKeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyCombo.self, from: data)
    }

    // MARK: - Launch at login

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                Log.app.warning("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
