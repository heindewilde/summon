import Foundation

/// A parsed search query. Filters are expressed inline so you never leave the
/// keyboard: `#invoice`, `/Clients`, `img:`, `pdf:`, `txt:`, `file:`.
public struct Query: Sendable, Equatable {
    public var text: String = ""
    public var kinds: Set<ItemKind> = []
    public var tags: [String] = []
    public var folder: String?
    public var pinnedOnly: Bool = false
    public var sensitiveOnly: Bool = false

    public var isEmpty: Bool {
        text.isEmpty && kinds.isEmpty && tags.isEmpty && folder == nil
            && !pinnedOnly && !sensitiveOnly
    }

    public var hasFilters: Bool {
        !kinds.isEmpty || !tags.isEmpty || folder != nil || pinnedOnly || sensitiveOnly
    }

    public static func parse(_ raw: String) -> Query {
        var query = Query()
        var freeText: [String] = []

        for token in raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            if token.hasPrefix("#"), token.count > 1 {
                query.tags.append(String(token.dropFirst()).lowercased())
                continue
            }
            if token.hasPrefix("/"), token.count > 1 {
                query.folder = String(token.dropFirst())
                continue
            }
            if token == "pinned:" || token == "pinned" && raw.contains("pinned:") {
                query.pinnedOnly = true
                continue
            }

            if let colon = token.firstIndex(of: ":") {
                let key = String(token[token.startIndex..<colon]).lowercased()
                let rest = String(token[token.index(after: colon)...])
                if let kinds = kindsForToken(key) {
                    query.kinds.formUnion(kinds)
                    if !rest.isEmpty { freeText.append(rest) }
                    continue
                }
                if key == "pinned" {
                    query.pinnedOnly = true
                    if !rest.isEmpty { freeText.append(rest) }
                    continue
                }
                if key == "locked" || key == "sensitive" {
                    query.sensitiveOnly = true
                    if !rest.isEmpty { freeText.append(rest) }
                    continue
                }
            }
            freeText.append(token)
        }

        query.text = freeText.joined(separator: " ")
        return query
    }

    private static func kindsForToken(_ key: String) -> Set<ItemKind>? {
        switch key {
        case "txt", "text", "snippet": [.text, .richText]
        case "img", "image", "photo": [.image]
        case "doc", "document", "pdf": [.document]
        case "file": [.file]
        default: nil
        }
    }

    /// Human-readable chips for the filters currently in effect.
    public var filterChips: [String] {
        var chips: [String] = []
        for kind in kinds.sorted(by: { $0.rawValue < $1.rawValue }) { chips.append(kind.pluralName) }
        chips.append(contentsOf: tags.map { "#\($0)" })
        if let folder { chips.append("in \(folder)") }
        if pinnedOnly { chips.append("Pinned") }
        if sensitiveOnly { chips.append("Sensitive") }
        return chips
    }
}
