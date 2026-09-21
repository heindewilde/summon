import SummonKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Add to Summon" in every share sheet.
///
/// Deliberately small: it reads what was shared, hands it to `Ingestion`, says what
/// happened, and gets out of the way. An extension has seconds and tens of megabytes,
/// so it never builds the app's model, never opens a CloudKit-backed store, and never
/// migrates — the container app exports what lands here the next time it runs.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(
            save: { [weak self] in try await self?.save() ?? "" },
            done: { [weak self] in self?.finish() }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// `loadItem`'s async form does not compose with a cast, so this wraps the
    /// callback once rather than at each call site.
    private func loadItem<T: Sendable>(_ provider: NSItemProvider, _ type: UTType,
                                       as: T.Type) async -> T? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { value, _ in
                // `value` is `NSSecureCoding`, which carries no Sendable promise, so
                // the cast happens here and only the result — a URL or a String —
                // crosses back.
                continuation.resume(returning: value as? T)
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, _ type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Reads the attachment, most specific kind first: a file beats an image beats
    /// text, because a shared PDF also offers a URL and a title, and saving those
    /// instead of the document is the wrong answer.
    @MainActor
    private func save() async throws -> String {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        let ingestion = try Ingestion()

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadItem(provider, .fileURL, as: URL.self) {
                return try await ingestion.save(.files([url]))
            }
        }
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadData(provider, .image) {
                return try await ingestion.save(.image(data))
            }
        }
        for provider in attachments {
            if let text = await loadItem(provider, .plainText, as: String.self) {
                return try await ingestion.save(.text(text, rtf: nil))
            }
            if let url = await loadItem(provider, .url, as: URL.self) {
                return try await ingestion.save(.text(url.absoluteString, rtf: nil))
            }
        }
        throw Ingestion.Failure.nothingUsable
    }
}

/// What the sheet shows while it works. Three states and nothing else: a share sheet
/// that asks questions is a share sheet you stop using.
private struct ShareView: View {
    let save: () async throws -> String
    let done: () -> Void

    @SwiftUI.State private var state: Progress = .saving

    /// Named `Progress` rather than `State`: a nested type called State shadows the
    /// property wrapper inside its own view.
    private enum Progress {
        case saving
        case saved(String)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .saving:
                ProgressView()
                Text("Saving to Summon…")
            case .saved(let title):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Saved “\(title)”").font(.headline).multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Close", action: done).buttonStyle(.bordered)
            }
        }
        .padding(32)
        .task {
            do {
                let title = try await save()
                state = .saved(title)
                // Long enough to read, short enough not to be in the way.
                try? await Task.sleep(for: .milliseconds(900))
                done()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
