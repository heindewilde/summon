import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds the `NSItemProvider` behind a dragged row.
///
/// A row has to carry the actual content: a document drag must hand the receiving
/// app a real file, and a snippet drag must hand it the snippet's text — not the
/// item's title, which is all a naive `ProxyRepresentation` on the row model gives.
public enum DragProvider {

    public static func make(for payload: InsertPayload, title: String) -> NSItemProvider? {
        // A file drags as a file. Mail attaches it, Finder copies it, upload fields
        // accept it — none of which work if all we vend is a string.
        if let url = payload.fileURL, FileManager.default.fileExists(atPath: url.path) {
            let provider = NSItemProvider(contentsOf: url)
            provider?.suggestedName = url.lastPathComponent
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

        return registeredSomething ? provider : nil
    }
}
