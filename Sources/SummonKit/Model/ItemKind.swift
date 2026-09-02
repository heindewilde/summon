import Foundation
import UniformTypeIdentifiers

/// The five things Summon holds. Deliberately few — this is not a file manager.
public enum ItemKind: String, Codable, CaseIterable, Sendable, Hashable {
    case text
    case richText
    case image
    case document
    case file

    public var displayName: String {
        switch self {
        case .text: "Snippet"
        case .richText: "Rich Snippet"
        case .image: "Image"
        case .document: "Document"
        case .file: "File"
        }
    }

    public var pluralName: String {
        switch self {
        case .text: "Snippets"
        case .richText: "Rich Snippets"
        case .image: "Images"
        case .document: "Documents"
        case .file: "Files"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .image: "photo"
        case .document: "doc.richtext"
        case .file: "doc"
        }
    }

    /// True when the payload lives in a blob file rather than in the database.
    public var isBlobBacked: Bool {
        switch self {
        case .text, .richText: false
        case .image, .document, .file: true
        }
    }

    public var isTextual: Bool { !isBlobBacked }

    /// Query prefix used to filter for this kind, e.g. `img:`.
    public var queryToken: String {
        switch self {
        case .text, .richText: "txt"
        case .image: "img"
        case .document: "doc"
        case .file: "file"
        }
    }

    /// Classify an imported file by its uniform type.
    public static func forFile(at url: URL) -> ItemKind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .file }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent)
            || type.conforms(to: .rtf) || type.conforms(to: .text) { return .document }
        return .file
    }
}
