import Foundation

/// One thing that was on the clipboard.
///
/// Plain data, and deliberately not nested inside `ClipboardMonitor`: the monitor
/// polls `NSPasteboard` and belongs to the Mac, while an entry is just a captured
/// value that `AppModel` files, the importer promotes into an item, and any platform
/// could produce — iOS has no background clipboard watching, but it can still offer
/// what you just copied.
public struct ClipboardEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let capturedAt: Date
    public let kind: ItemKind
    public let text: String?
    public let rtf: Data?
    public let imageData: Data?
    public let fileURL: URL?
    public let sourceBundleID: String?
    public let sourceAppName: String?

    public var preview: String {
        if let fileURL { return fileURL.lastPathComponent }
        if imageData != nil { return "Image" }
        let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Empty" : String(t.prefix(200))
    }

    public init(id: UUID = UUID(), capturedAt: Date, kind: ItemKind, text: String? = nil,
                rtf: Data? = nil, imageData: Data? = nil, fileURL: URL? = nil,
                sourceBundleID: String? = nil, sourceAppName: String? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.imageData = imageData
        self.fileURL = fileURL
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }

    public var suggestedTitle: String {
        if let fileURL { return fileURL.deletingPathExtension().lastPathComponent }
        if imageData != nil {
            return "Image from \(sourceAppName ?? "clipboard")"
        }
        return Heuristics.title(forText: text ?? "")
    }
}
