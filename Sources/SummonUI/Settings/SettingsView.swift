import AppKit
import SwiftUI
import SummonKit

public struct SettingsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettings(model: model)
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            PrivacySettings(model: model)
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            IntelligenceSettings(model: model)
                .tabItem { Label("Intelligence", systemImage: "sparkles") }
        }
        .frame(width: 560, height: 420)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Summon panel") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.summonHotKey },
                        set: { model.settings.summonHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
                LabeledContent("Save selection") {
                    HotKeyRecorder(combo: Binding(
                        get: { model.settings.quickSaveHotKey },
                        set: { model.settings.quickSaveHotKey = $0 }
                    )) { _ in model.reregisterHotKeys() }
                }
                Toggle("Enable the save-selection shortcut", isOn: Binding(
                    get: { model.settings.quickSaveEnabled },
                    set: { model.settings.quickSaveEnabled = $0; model.reregisterHotKeys() }
                ))
            }

            Section("Inserting") {
                Toggle("Paste straight into the app I was in", isOn: Binding(
                    get: { model.settings.autoPaste },
                    set: { model.settings.autoPaste = $0 }
                ))
                accessibilityStatus
            }

            Section("Appearance") {
                Toggle("Show in the Dock", isOn: Binding(
                    get: { model.settings.showDockIcon },
                    set: {
                        model.settings.showDockIcon = $0
                        NSApp.setActivationPolicy($0 ? .regular : .accessory)
                    }
                ))
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, new in model.settings.launchAtLogin = new }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = model.settings.launchAtLogin }
    }

    @ViewBuilder
    private var accessibilityStatus: some View {
        if Inserter.hasAccessibility {
            Label("Accessibility allowed — Summon can paste for you.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.success)
        } else {
            HStack(alignment: .top) {
                Label("Summon will copy instead of pasting until Accessibility is allowed.",
                      systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.spark)
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
        Form {
            Section("Clipboard history") {
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
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)

                Button("Clear history now") { model.clipboard.clear() }
                    .controlSize(.small)
            }

            Section("Storage") {
                LabeledContent("Items", value: "\(model.store.snapshots.count)")
                LabeledContent("On disk",
                               value: ByteCountFormatter.string(fromByteCount: Int64(totalBytes),
                                                                countStyle: .file))
                LabeledContent("Location") {
                    Button(model.paths.root.path(percentEncoded: false)) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.paths.root])
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Text("Files you add are copied here, so moving or deleting the originals later never breaks an item.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .formStyle(.grouped)
        .task { totalBytes = model.store.files.totalBytes() }
    }
}

struct PrivacySettings: View {
    @Bindable var model: AppModel
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var currentPIN = ""
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section("Sensitive items") {
                if model.vault.isConfigured {
                    LabeledContent("Status") {
                        Label(model.vault.isUnlocked ? "Unlocked" : "Locked",
                              systemImage: model.vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                            .foregroundStyle(model.vault.isUnlocked ? Theme.success : Theme.spark)
                    }

                    if Vault.biometricsAvailable {
                        Toggle("Unlock with Touch ID", isOn: Binding(
                            get: { model.vault.biometricsEnabled },
                            set: { enabled in
                                if enabled {
                                    guard model.vault.isUnlocked else {
                                        report("Unlock first, then enable Touch ID.", error: true)
                                        return
                                    }
                                    do { try model.vault.enableBiometricUnlock(); report("Touch ID enabled.") }
                                    catch { report(error.localizedDescription, error: true) }
                                } else {
                                    model.vault.disableBiometricUnlock()
                                    report("Touch ID disabled.")
                                }
                            }
                        ))
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

                    LabeledContent("Change PIN") {
                        VStack(alignment: .trailing, spacing: 4) {
                            SecureField("Current", text: $currentPIN).frame(width: 150)
                            SecureField("New", text: $newPIN).frame(width: 150)
                            SecureField("Confirm", text: $confirmPIN).frame(width: 150)
                            Button("Change") { changePIN() }
                                .controlSize(.small)
                                .disabled(newPIN.count < 4 || newPIN != confirmPIN)
                        }
                    }
                } else {
                    Text("No PIN set. Marking anything sensitive will ask for one.")
                        .font(.system(size: 12))
                    LabeledContent("Set a PIN") {
                        VStack(alignment: .trailing, spacing: 4) {
                            SecureField("PIN", text: $newPIN).frame(width: 150)
                            SecureField("Confirm", text: $confirmPIN).frame(width: 150)
                            Button("Set PIN") { setPIN() }
                                .controlSize(.small)
                                .disabled(newPIN.count < 4 || newPIN != confirmPIN)
                        }
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(isError ? Theme.danger : Theme.success)
                }
            }

            Section("How it works") {
                Text("""
                Sensitive contents are encrypted with AES-GCM under a key derived from your \
                PIN, and the key exists in memory only while unlocked. Titles and tags stay \
                readable so you can still find things; bodies, files and extracted text do not.

                Summon never makes a network request. There are no accounts and no sync.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .formStyle(.grouped)
    }

    private func report(_ text: String, error: Bool = false) {
        message = text
        isError = error
    }

    private func setPIN() {
        do {
            try model.vault.setUpPIN(newPIN)
            newPIN = ""; confirmPIN = ""
            report("PIN set. Sensitive items are now encrypted.")
        } catch {
            report((error as? VaultError)?.errorDescription ?? error.localizedDescription, error: true)
        }
    }

    private func changePIN() {
        do {
            try model.vault.changePIN(current: currentPIN, new: newPIN)
            currentPIN = ""; newPIN = ""; confirmPIN = ""
            report("PIN changed.")
        } catch {
            report((error as? VaultError)?.errorDescription ?? error.localizedDescription, error: true)
        }
    }
}

struct IntelligenceSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("On-device intelligence") {
                Toggle("Use Apple’s on-device model", isOn: Binding(
                    get: { model.settings.intelligenceEnabled },
                    set: {
                        model.settings.intelligenceEnabled = $0
                        model.applySettings()
                        model.intelligence.refreshStatus()
                    }
                ))

                LabeledContent("Status") {
                    Label(statusText, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                        .font(.system(size: 11.5))
                }

                Text(model.intelligence.status.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("What it does") {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    row("text.badge.checkmark", "Suggests a title, tags and a one-line summary when you save something.")
                    row("wand.and.sparkles", "Rewrites a snippet in a different register, from the item editor.")
                    row("doc.text.viewfinder", "Reads text out of images and PDFs with Vision, so their contents are searchable.")
                }
                .font(.system(size: 11.5))
            }

            Section("Always true") {
                Text("""
                Everything runs on this Mac. Content marked sensitive is never handed to the \
                model, even locally. When the model is unavailable, Summon falls back to \
                built-in rules — you lose the suggestions, not the feature.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 18)
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
        case .unavailable: Theme.spark
        }
    }
}
