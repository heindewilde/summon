import AppKit
import SummonKit
import UniformTypeIdentifiers
import UserNotifications

/// "Add to Summon" in Finder's right-click menu, under Quick Actions.
///
/// This is what replaces reading the Finder selection over Apple Events, which needed
/// a temporary exception the App Store does not allow (docs/sandbox-spike.md). The
/// difference is who starts it: Summon no longer asks Finder what is selected, Finder
/// hands the files over. Same result, no exception, and it works from any app with a
/// Share menu rather than only from Finder.
final class ActionViewController: NSViewController {
    override func loadView() {
        // No interface: Finder's menu item is the interface. A window here would be a
        // dialog nobody asked for, in front of the thing they were doing.
        view = NSView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await run() }
    }

    @MainActor
    private func run() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var saved = 0

        do {
            let ingestion = try Ingestion()
            for provider in providers {
                guard let url = await load(provider) else { continue }
                _ = try? await ingestion.save(.files([url]))
                saved += 1
            }
        } catch {
            notify("Summon couldn’t save that", error.localizedDescription)
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        notify(saved == 1 ? "Saved to Summon" : "Saved \(saved) items to Summon",
               saved == 0 ? "There was nothing Summon could read." : "")
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func load(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                if let url = value as? URL {
                    continuation.resume(returning: url)
                } else if let data = value as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The extension has no window, so the confirmation is a notification rather than
    /// nothing at all — a Quick Action that appears to do nothing is one nobody trusts.
    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(request)
        }
    }
}
