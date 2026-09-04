import ImageIO
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
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

    /// False in the library, where the tag field sits directly below and showed the
    /// same tags twice. True in the panel, which has no field and where the chips are
    /// the only place tags appear at all.
    public let showsTags: Bool

    public init(snapshot: ItemSnapshot, bodyText: String?, fileURL: URL?,
                thumbnailURL: URL?, showsTags: Bool = true) {
        self.snapshot = snapshot
        self.bodyText = bodyText
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.showsTags = showsTags
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if hasMetadata {
                Rule()
                metadata
            }
        }
    }

    private var hasMetadata: Bool {
        !(snapshot.summary ?? "").isEmpty || (showsTags && !snapshot.tagNames.isEmpty)
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
                .font(Theme.Icon.hero.weight(.light))
                .foregroundStyle(Theme.secondaryText)
            Text("Contents are locked")
                .font(Theme.Typography.body.weight(.medium))
            Text("Press ↩ to unlock with Touch ID, a PIN or a passphrase.")
                .font(Theme.Typography.caption)
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

    /// Decoded through ImageIO rather than NSImage: same result, no AppKit, and no
    /// window-server dependency in a view that may be drawn while snapshotting.
    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private var imagePreview: some View {
        Group {
            if let url = fileURL ?? thumbnailURL, let image = Self.decode(url) {
                Image(decorative: image, scale: 1)
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
                        .font(Theme.Typography.body)
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
                // macOS can ask the workspace for the document's real icon. iOS has no
                // equivalent — a file has no per-app icon there — so it gets the same
                // kind glyph the rest of the app uses.
                #if canImport(AppKit)
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 64, height: 64)
                #else
                Image(systemName: "doc")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 64, height: 64)
                #endif
                Text(url.lastPathComponent)
                    .font(Theme.Typography.body.weight(.medium))
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

    /// The summary, and the tags where they are the only place tags are visible.
    ///
    /// It used to also name the kind and count how often the item had been used. The
    /// kind is already drawn as a badge on every row and glyph above every preview,
    /// so naming it made "image" appear three times in one pane; the use count was
    /// something to read rather than something to act on.
    @ViewBuilder
    private var metadata: some View {
        let summary = snapshot.summary ?? ""
        let showsAnything = !summary.isEmpty || (showsTags && !snapshot.tagNames.isEmpty)

        if showsAnything {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                if !summary.isEmpty {
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsTags && !snapshot.tagNames.isEmpty {
                    HStack(spacing: Theme.Space.xxs) {
                        ForEach(snapshot.tagNames.prefix(4), id: \.self) { TagChip(name: $0) }
                    }
                }
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                if let rendered = PDFPreview.render(page, scale: 1.6) {
                    Image(decorative: rendered, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            } else {
                Color.clear
            }
        } else {
            PDFViewRepresentable(url: url)
        }
    }
}

extension PDFPreview {
    /// A page drawn into a bitmap, for the snapshot path that cannot host a PDFView.
    ///
    /// `PDFPage.thumbnail(of:for:)` would be shorter and returns an NSImage on macOS
    /// and a UIImage on iOS — a platform-shaped return in the middle of a shared view.
    /// Drawing into a CGContext is the same work without that.
    static func render(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let size = CGSize(width: (bounds.width * scale).rounded(),
                          height: (bounds.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }
}

/// PDFKit ships PDFView on both platforms; only the representable protocol differs.
#if canImport(AppKit)
struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView { Self.make(url) }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#else
struct PDFViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView { Self.make(url) }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif

extension PDFViewRepresentable {
    static func make(_ url: URL) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }
}
