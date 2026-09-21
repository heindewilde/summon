// SwiftPM builds every target for the host, so the guard stays even though this
// target is only ever linked by the iOS app.
#if !canImport(AppKit)
import SummonKit
import SummonUI
import SwiftUI

/// Settings, on a phone.
///
/// Deliberately shorter than the Mac's: hot keys, the clipboard tray, the dock icon
/// and auto-paste are all answers to questions a phone does not ask. What is left is
/// what travels — the vault, what it seals, and how it looks.
struct PhoneSettingsView: View {
    @Bindable var model: AppModel
    let dismiss: () -> Void

    /// Whether this device can be told about the other one's changes as they happen,
    /// rather than finding out when Summon is next opened.
    @State private var organising = false

    private var pushStatus: String {
        UserDefaults.standard.string(forKey: "sync.pushStatus") ?? "Checking…"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sensitive items") {
                    if model.vault.isConfigured {
                        LabeledContent("Status",
                                       value: model.vault.isUnlocked ? "Unlocked" : "Locked")
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
                            Toggle("Unlock with \(Biometry.name)", isOn: Binding(
                                get: { model.vault.biometricsEnabled },
                                set: { enabled in
                                    if enabled {
                                        guard model.vault.isUnlocked else {
                                            model.show(Toast(text: "Unlock first", symbol: "lock",
                                                             tone: .warning))
                                            return
                                        }
                                        try? model.vault.enableBiometricUnlock()
                                    } else {
                                        model.vault.disableBiometricUnlock()
                                    }
                                }
                            ))
                        }
                        Button("Change \(model.vault.secretKind.noun)") { model.beginChangeSecret() }
                    } else {
                        // The PIN is per-device: it wraps a key this account already
                        // has, so setting one here opens the items that synced from
                        // the Mac rather than starting a second, separate vault.
                        Button("Set a PIN") { model.beginPINSetup() }
                    }
                }

                Section {
                    Toggle("Encrypt everything", isOn: Binding(
                        get: { model.settings.encryptEverything },
                        set: { model.setEncryptEverything($0) }
                    ))
                } footer: {
                    Text("""
                    Sensitive items are always encrypted. Turn this on and the whole \
                    library is, so nothing readable leaves your devices — including \
                    when it syncs.
                    """)
                }

                Section {
                    Button("Folders & Tags…", systemImage: "folder.badge.gearshape") {
                        organising = true
                    }
                } footer: {
                    Text("Create, rename, nest and recolour folders, and tidy up tags.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { model.settings.appearance },
                        set: { model.settings.appearance = $0 }
                    )) {
                        ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                }

                Section("iCloud") {
                    LabeledContent("Sync", value: model.store.syncStatus?.summary ?? "Waiting…")
                    LabeledContent("Live updates", value: pushStatus)
                    if let error = model.store.syncStatus?.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("About") {
                    LabeledContent("Items", value: "\(model.store.snapshots.count)")
                    Link("summon.technology", destination: URL(string: "https://summon.technology")!)
                    Link("Support", destination: URL(string: "https://summon.technology/support")!)
                }
            }
            // Presented here rather than by the root: a view can only present one
            // sheet at a time, and the root is covered by this one — which is why
            // "Set a PIN" appeared to do nothing at all.
            .sheet(item: Binding(get: { model.lockSheet },
                                 set: { if $0 == nil { model.cancelLockSheet() } })) { purpose in
                LockSheet(model: model, purpose: purpose) { model.finishLockSheet() }
            }
            .sheet(isPresented: $organising) {
                FolderManagerView(model: model) { organising = false }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
