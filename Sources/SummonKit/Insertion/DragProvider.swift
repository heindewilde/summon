import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds the `NSItemProvider` behind a dragged row.
///
/// A row has to carry the actual content: a document drag must hand the receiving
/// app a real file, and a snippet drag must hand it the snippet's text — not the
/// item's title, which is all a naive `ProxyRepresentation` on the row model gives.
public enum DragProvider {

    /// - Parameter itemID: stamped onto the provider so a drop back into Summon can
    ///   tell *which* row it is holding. Without it a drag onto a folder looked like
    ///   an anonymous file or a piece of text, and filing it was guesswork.
    public static func make(for payload: InsertPayload, title: String,
                            itemID: UUID? = nil) -> NSItemProvider? {
        // A file drags as a file. Mail attaches it, Finder copies it, upload fields
        // accept it — none of which work if all we vend is a string.
        if let url = payload.fileURL, FileManager.default.fileExists(atPath: url.path) {
            let provider = NSItemProvider(contentsOf: url)
            provider?.suggestedName = url.lastPathComponent
            if let itemID { provider?.registerSummonID(itemID, as: SummonDragType.item) }
            return provider
        }

        let provider = NSItemProvider()
        var registeredSomething = false

        if let rtf = payload.rtf {
            provider.registerDataRepresentation(for: .rtf) { completion in
                completion(rtf, nil)
                return nil
            }
            registeredSomething = true
        }
        if let text = payload.plainText, !text.isEmpty {
            provider.registerObject(text as NSString, visibility: .all)
            provider.suggestedName = title
            registeredSomething = true
        }

        guard registeredSomething else { return nil }
        if let itemID { provider.registerSummonID(itemID, as: SummonDragType.item) }
        return provider
    }
}
