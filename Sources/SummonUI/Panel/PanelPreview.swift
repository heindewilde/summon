import AppKit
import PDFKit
import SwiftUI
import SummonKit

/// The right-hand preview. Shows enough to be sure it is the right thing, without
/// pretending to be a document viewer.
public struct PanelPreview: View {
    public let snapshot: ItemSnapshot
    public let bodyText: String?
    public let fileURL: URL?
    public let thumbnailURL: URL?

    public init(snapshot: ItemSnapshot, bodyText: String?, fileURL: URL?, thumbnailURL: URL?) {
        self.snapshot = snapshot
        self.bodyText = bodyText
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider().overlay(Theme.hairline)
            metadata
        }
    }

    @ViewBuilder
    private var content: some View {
        if snapshot.isLocked {
            lockedState
        } else {
            switch snapshot.kind {
            case .text, .richText:
                textPreview
            case .image:
                imagePreview
            case .document:
                documentPreview
            case .file:
                filePreview
            }
        }
    }

    private var lockedState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text("Contents are locked")
                .font(.system(size: 12.5, weight: .medium))
            Text("Press ↩ to unlock with Touch ID or your PIN.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.m)
    }

    private var textPreview: some View {
        SnapshotSafeScrollView {
            PlaceholderHighlightedText(text: bodyText ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m)
        }
    }

    private var imagePreview: some View {
        Group {
            if let url = fileURL ?? thumbnailURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Space.m)
            } else {
                placeholderGlyph
            }
        }
    }

    private var documentPreview: some View {
        Group {
            if let url = fileURL, url.pathExtension.lowercased() == "pdf" {
                PDFPreview(url: url)
                    .padding(Theme.Space.xs)
            } else if let text = bodyText ?? snapshot.summary, !text.isEmpty {
                SnapshotSafeScrollView {
                    Text(text)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.m)
                }
            } else {
                placeholderGlyph
            }
        }
    }

    private var filePreview: some View {
        VStack(spacing: Theme.Space.s) {
            if let url = fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                placeholderGlyph
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.m)
    }

    private var placeholderGlyph: some View {
        KindBadge(kind: snapshot.kind, size: 54)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let summary = snapshot.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !snapshot.tagNames.isEmpty {
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(snapshot.tagNames.prefix(4), id: \.self) { TagChip(name: $0) }
                }
            }

            HStack(spacing: Theme.Space.s) {
                Label(snapshot.kind.displayName, systemImage: snapshot.kind.symbolName)
                if snapshot.useCount > 0 {
                    Label("Used \(snapshot.useCount)×", systemImage: "arrow.uturn.backward")
                }
                if let last = snapshot.lastUsedAt {
                    Text(last.formatted(.relative(presentation: .named)))
                }
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.tertiaryText)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PDFPreview: View {
    let url: URL
    @Environment(\.isSnapshotting) private var isSnapshotting

    var body: some View {
        if isSnapshotting {
            // ImageRenderer cannot draw a PDFView, so render page one as an image.
            // The document must outlive the page, or PDFKit draws nothing.
            if let document = PDFDocument(url: url), let page = document.page(at: 0) {
                let bounds = page.bounds(for: .mediaBox)
                Image(nsImage: page.thumbnail(of: CGSize(width: bounds.width * 1.6,
                                                         height: bounds.height * 1.6),
                                              for: .mediaBox))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        } else {
            PDFViewRepresentable(url: url)
        }
    }
}

struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
