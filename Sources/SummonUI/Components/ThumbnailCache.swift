import AppKit
import SummonKit
import SwiftUI

/// `CGImage` is immutable once created, so handing one across an isolation boundary
/// is safe. Narrow and documented rather than blanket.
private struct SendableCGImage: @unchecked Sendable {
    let image: CGImage
}

/// In-memory thumbnails, decoded once and downsampled at decode time.
///
/// Before this, every row called `FileManager.fileExists` and then
/// `NSImage(contentsOf:)` *inside* `body` — a synchronous disk read and a
/// full-resolution decode per row, per render, repeated on every keystroke. Stored
/// thumbnails are up to 512px and were being drawn at 32pt.
///
/// A `@MainActor` class rather than an `actor`, because `NSImage` is not `Sendable`
/// and every consumer is a view. Only the decode leaves the main actor.
@MainActor
public final class ThumbnailCache {
    public static let shared = ThumbnailCache()

    private let images = NSCache<NSUUID, NSImage>()
    /// Remembers absence too, so a missing thumbnail is not re-probed on every render.
    private var missing: Set<UUID> = []
    private var inFlight: [UUID: Task<NSImage?, Never>] = [:]

    public init() {
        images.countLimit = 512
    }

    /// Synchronous and free of I/O. `nil` means "not in memory yet", never "no
    /// thumbnail" — that distinction is what lets a warm row paint without flicker.
    public func cached(_ id: UUID) -> NSImage? {
        images.object(forKey: id as NSUUID)
    }

    public func isKnownMissing(_ id: UUID) -> Bool { missing.contains(id) }

    /// Decodes downsampled, off the main actor, coalescing concurrent requests.
    public func image(for id: UUID, url: URL, pointSize: CGFloat) async -> NSImage? {
        if let hit = cached(id) { return hit }
        if missing.contains(id) { return nil }
        if let existing = inFlight[id] { return await existing.value }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = Int((pointSize * scale).rounded())

        let task = Task<NSImage?, Never> { [weak self] in
            let decoded = await Task.detached(priority: .utility) { () -> SendableCGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ]
                return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                    .map(SendableCGImage.init)
            }.value

            guard let self else { return nil }
            guard let decoded else {
                self.missing.insert(id)
                self.inFlight[id] = nil
                return nil
            }
            let image = NSImage(cgImage: decoded.image,
                                size: NSSize(width: pointSize, height: pointSize))
            self.images.setObject(image, forKey: id as NSUUID)
            self.inFlight[id] = nil
            return image
        }
        inFlight[id] = task
        return await task.value
    }

    public func invalidate(_ id: UUID) {
        images.removeObject(forKey: id as NSUUID)
        missing.remove(id)
        inFlight[id]?.cancel()
        inFlight[id] = nil
    }

    /// Called when the vault locks: thumbnails of sensitive items must not survive in
    /// memory once their contents are no longer unlocked.
    public func invalidateAll() {
        images.removeAllObjects()
        missing.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}
