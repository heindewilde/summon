import AppKit
import Observation
import ServiceManagement
import SummonKit
import SummonUI
import SummonKitMac

extension AppearanceChoice {
    /// Nil means "follow the system", which is what a nil `NSApp.appearance` does.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The preferences that only mean something on a Mac.
///
/// These lived in `AppSettings` and were the only reason a preferences object needed
/// AppKit, ServiceManagement and Carbon: a global shortcut, a login item, and the
/// appearance applied to `NSApp`. None of the three has an iOS reading — a phone has
/// no system-wide shortcut to register and no login to launch at.
///
/// A shared instance rather than a property on `AppModel`, because `AppModel` is the
/// cross-platform controller and cannot name a type from this target. Same shape as
/// `HotKeyCenter.shared`, and for the same reason: there is exactly one of these per
/// running app.
///
/// The UserDefaults keys are unchanged, so a library that already has shortcuts bound
/// keeps them across this move.
@MainActor
@Observable
public final class MacSettings {
    public static let shared = MacSettings()

    private let defaults = UserDefaults.standard

    public var summonHotKey: HotKeyCombo {
        didSet { store(summonHotKey, "hotkey.summon"); publishLabels() }
    }
    public var quickSaveHotKey: HotKeyCombo {
        didSet { store(quickSaveHotKey, "hotkey.quickSave"); publishLabels() }
    }

    @ObservationIgnored private weak var model: AppModel?

    private init() {
        summonHotKey = MacSettings.load("hotkey.summon") ?? .defaultSummon
        quickSaveHotKey = MacSettings.load("hotkey.quickSave") ?? .defaultQuickSave
    }

    /// Hands `AppModel` the two shortcut labels, and keeps them current.
    ///
    /// The cross-platform views name these shortcuts in their empty states — "press
    /// ⌥Space from wherever you're working". They cannot read a `HotKeyCombo`, which
    /// is Carbon down to its modifier mask, so what crosses the boundary is the
    /// rendered string and nothing else. On iOS it stays nil and those sentences
    /// leave themselves out.
    public func bind(to model: AppModel) {
        self.model = model
        publishLabels()
        model.settings.appearanceDidChange = { NSApp?.appearance = $0.nsAppearance }
        model.settings.applyAppearance()
    }

    private func publishLabels() {
        model?.summonShortcutLabel = summonHotKey.displayString
        model?.quickSaveShortcutLabel = quickSaveHotKey.displayString
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
