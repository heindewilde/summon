import AppKit
import SwiftUI
import SummonKit
import SummonUI
import SummonKitMac

public struct SettingsView: View {
    @Bindable var model: AppModel

    /// Which tab is showing. Bound rather than left to the TabView so a screenshot
    /// harness can open the one being reviewed.
    @State private var tab: Tab

    public enum Tab: String, Hashable { case general, library, privacy, intelligence }

    public init(model: AppModel, tab: Tab = .general) {
        self.model = model
        _tab = State(initialValue: tab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsTabRail(selection: $tab, tabs: [
                (.general, "General", "gearshape"),
                (.library, "Library", "square.grid.2x2"),
                (.privacy, "Privacy", "lock.shield"),
                (.intelligence, "Intelligence", "sparkles"),
            ])
            switch tab {
            case .general: GeneralSettings(model: model)
            case .library: LibrarySettings(model: model)
            case .privacy: PrivacySettings(model: model)
            case .intelligence: IntelligenceSettings(model: model)
            }
        }
        .frame(width: 560, height: 460)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = false

    var body: some View {
        SettingsPage {
            SettingsSection("Shortcuts") {
                SettingsRow("Summon panel") {
                    HotKeyRecorder(combo: Binding(
                        get: { MacSettings.shared.summonHotKey },
                        set: { MacSettings.shared.summonHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
                SettingsRow("Save selection") {
                    HotKeyRecorder(combo: Binding(
                        get: { MacSettings.shared.quickSaveHotKey },
                        set: { MacSettings.shared.quickSaveHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
                Toggle("Enable the save-selection shortcut", isOn: Binding(
                    get: { model.settings.quickSaveEnabled },
                    set: { model.settings.quickSaveEnabled = $0; model.reregisterHotKeys() }
                ))
            }

            SettingsSection("Inserting") {
                Toggle("Paste straight into the app I was in", isOn: Binding(
                    get: { model.settings.autoPaste },
                    set: { model.settings.autoPaste = $0 }
                ))
                accessibilityStatus
            }

            SettingsSection("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { model.settings.appearance },
                    set: { model.settings.appearance = $0 }
                )) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show in the Dock", isOn: Binding(
                    get: { model.settings.showDockIcon },
                    set: {
                        model.settings.showDockIcon = $0
                        NSApp.setActivationPolicy($0 ? .regular : .accessory)
                    }
                ))
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in MacSettings.shared.launchAtLogin = new }
            }
        }
        .onAppear { launchAtLogin = MacSettings.shared.launchAtLogin }
    }

    @ViewBuilder
    private var accessibilityStatus: some View {
        if Inserter.hasAccessibility {
            Label("Accessibility allowed — Summon can paste for you.", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.success)
        } else {
            HStack(alignment: .top) {
                Label("Summon will copy instead of pasting until Accessibility is allowed.",
                      systemImage: "info.circle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("Open Settings…") { Inserter.openAccessibilitySettings() }
                    .controlSize(.small)
            }
        }
    }
}

struct LibrarySettings: View {
    @Bindable var model: AppModel
    @State private var totalBytes = 0

    var body: some View {
        SettingsPage {
            SettingsSection("Clipboard history") {
                Toggle("Keep a history of what I copy", isOn: Binding(
                    get: { model.settings.clipboardHistoryEnabled },
                    set: { model.settings.clipboardHistoryEnabled = $0; model.applySettings() }
                ))
                Toggle("Keep history between launches", isOn: Binding(
                    get: { model.settings.clipboardPersists },
                    set: { model.settings.clipboardPersists = $0; model.applySettings() }
                ))
                .disabled(!model.settings.clipboardHistoryEnabled)

                Stepper("Remember \(model.settings.clipboardLimit) items", value: Binding(
                    get: { model.settings.clipboardLimit },
                    set: { model.settings.clipboardLimit = $0; model.applySettings() }
                ), in: 10...200, step: 10)
                .disabled(!model.settings.clipboardHistoryEnabled)

                Text("Copies marked concealed by the source app — password managers, mostly — are never recorded. Off by default between launches, because a clipboard log that survives reboots is not something to switch on for you.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)

                Button("Clear history now") { model.clipboard.clear() }
                    .controlSize(.small)
            }

            SettingsSection("Storage") {
                SettingsRow("Items", value: "\(model.store.snapshots.count)")
                SettingsRow("On disk",
                               value: ByteCountFormatter.string(fromByteCount: Int64(totalBytes),
                                                                countStyle: .file))
                SettingsRow("Location") {
                    Button(model.paths.root.path(percentEncoded: false)) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.root])
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Text("Files you add are copied here, so moving or deleting the originals later never breaks an item.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .task { totalBytes = model.store.files.totalBytes() }
    }
}

struct PrivacySettings: View {
    @Bindable var model: AppModel
    @State private var sheet: LockSheet.Purpose?

    var body: some View {
        SettingsPage {
            if model.vault.isConfigured {
                configured
            } else {
                notConfigured
            }

            SettingsSection("How it works") {
                Text("""
                Sensitive contents are encrypted with AES-GCM under a key derived from your \
                PIN, and the key exists in memory only while unlocked. Titles and tags stay \
                readable so you can still find things; bodies, files and extracted text do not.

                Summon never makes a network request. There are no accounts and no sync.
                """)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .sheet(item: $sheet) { purpose in
            LockSheet(model: model, purpose: purpose) { sheet = nil }
        }
    }

    // MARK: - With a PIN set

    @ViewBuilder
    private var configured: some View {
        SettingsSection("Lock") {
            SettingsRow("Status") {
                HStack(spacing: Theme.Space.s) {
                    Label(model.vault.isUnlocked ? "Unlocked" : "Locked",
                          systemImage: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.secondaryText)
                    if model.vault.isUnlocked {
                        Button("Lock Now") { model.lockVaultNow() }
                            .controlSize(.small)
                    }
                }
            }

            Picker("Lock automatically after", selection: Binding(
                get: { model.settings.autoLockMinutes },
                set: { model.settings.autoLockMinutes = $0; model.applySettings() }
            )) {
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 hour").tag(60)
                Text("Never").tag(0)
            }

            if Vault.biometricStorageAvailable {
                Toggle("Unlock with Touch ID", isOn: Binding(
                    get: { model.vault.biometricsEnabled },
                    set: { enabled in
                        if enabled {
                            guard model.vault.isUnlocked else {
                                model.show(Toast(text: "Unlock first", symbol: "lock", tone: .warning))
                                return
                            }
                            do { try model.vault.enableBiometricUnlock() }
                            catch {
                                model.show(Toast(text: "Couldn’t enable Touch ID",
                                                 symbol: "exclamationmark.triangle", tone: .danger,
                                                 detail: error.localizedDescription))
                            }
                        } else {
                            model.vault.disableBiometricUnlock()
                        }
                    }
                ))
            } else if Vault.biometricsAvailable {
                Label("""
                Touch ID unlock needs an Apple Developer ID. A locally-signed build \
                can’t store a key behind the biometric sensor, so this Mac asks for \
                your \(model.vault.secretKind.noun).
                """, systemImage: "touchid")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }

        SettingsSection(model.vault.secretKind.displayName) {
            // What it actually protects, so the section is not an abstraction.
            SettingsRow("Protecting", value: protectedSummary)

            if model.vault.secretKind == .pin {
                // Said plainly rather than left implied. Four digits is 10,000
                // combinations, and the cooldown that makes that reasonable only
                // applies to someone typing into this app — not to someone who has
                // copied the library folder and can guess offline as fast as they like.
                //
                // A `Label` rather than bare `Text`, matching the Touch ID note above:
                // in a grouped form a bare Text sits outside the row inset and breaks
                // the card it appears to be part of.
                Label("""
                A PIN is quick, and enough to stop someone who wanders past your Mac. \
                A passphrase is what holds up if someone ever has a copy of your disk.
                """, systemImage: "key")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Unlabelled: these are actions, and inventing a noun for the left column
            // ("Four digits", "Protection") only made the rows read like settings.
            HStack {
                Spacer()
                Button("Change \(model.vault.secretKind.displayName)…") { sheet = .change }
                Button("Turn Off…", role: .destructive) { sheet = .turnOff }
            }
        }
    }

    // MARK: - With none

    @ViewBuilder
    private var notConfigured: some View {
        SettingsSection("Sensitive items") {
            SettingsRow("Lock") {
                Button("Set a PIN or passphrase…") { sheet = .create }
            }
            Text("Nothing is encrypted until you set one. Marking an item or a folder sensitive will ask for it.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var sensitiveItemCount: Int {
        model.store.snapshots.count(where: \.isSensitive)
    }

    private var sensitiveFolderCount: Int {
        model.store.allFolders().count { $0.isSensitive }
    }

    private var protectedSummary: String {
        let items = sensitiveItemCount
        let folders = sensitiveFolderCount
        if items == 0 && folders == 0 { return "Nothing yet" }
        var parts: [String] = []
        if items > 0 { parts.append(items == 1 ? "1 item" : "\(items) items") }
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders) folders") }
        return parts.joined(separator: " · ")
    }

}

struct IntelligenceSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsPage {
            SettingsSection("On-device intelligence") {
                Toggle("Use Apple’s on-device model", isOn: Binding(
                    get: { model.settings.intelligenceEnabled },
                    set: {
                        model.settings.intelligenceEnabled = $0
                        model.applySettings()
                        model.intelligence.refreshStatus()
                    }
                ))

                SettingsRow("Status") {
                    Label(statusText, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                        .font(Theme.Typography.caption)
                }

                Text(model.intelligence.status.explanation)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            SettingsSection("What it does") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    row("text.badge.checkmark", "Suggests a title, tags and a one-line summary when you save something.")
                    row("wand.and.sparkles", "Rewrites a snippet in a different register, from the item editor.")
                    row("doc.text.viewfinder", "Reads text out of images and PDFs with Vision, so their contents are searchable.")
                }
                .font(Theme.Typography.caption)
            }

            SettingsSection("Always true") {
                Text("""
                Everything runs on this Mac. Content marked sensitive is never handed to the \
                model, even locally. When the model is unavailable, Summon falls back to \
                built-in rules — you lose the suggestions, not the feature.
                """)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: symbol).foregroundStyle(Theme.primaryText).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var statusText: String {
        switch model.intelligence.status {
        case .ready: "Ready"
        case .disabled: "Turned off"
        case .unavailable: "Using built-in rules"
        }
    }

    private var statusSymbol: String {
        switch model.intelligence.status {
        case .ready: "checkmark.circle.fill"
        case .disabled: "minus.circle"
        case .unavailable: "info.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.intelligence.status {
        case .ready: Theme.success
        case .disabled: Theme.secondaryText
        case .unavailable: Theme.secondaryText
        }
    }
}
