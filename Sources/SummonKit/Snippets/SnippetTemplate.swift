import Foundation

/// A placeholder inside a snippet.
public enum SnippetToken: Sendable, Equatable {
    case literal(String)
    /// A fill-in field. Repeating the same name reuses one value.
    case field(name: String, defaultValue: String?)
    case date(offsetDays: Int)
    case time
    case clipboard
    /// Where the caret should land after insertion.
    case cursor
}

public struct SnippetField: Sendable, Equatable, Identifiable, Hashable {
    public let name: String
    public let defaultValue: String?
    public var id: String { name }

    public var label: String {
        // "first_name" and "firstName" both read as "First name".
        var spaced = name.replacingOccurrences(of: "_", with: " ")
        spaced = spaced.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2",
                                             options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }
}

public struct RenderContext: Sendable {
    public var now: Date
    public var clipboard: String
    public var locale: Locale

    public init(now: Date = Date(), clipboard: String = "", locale: Locale = .autoupdatingCurrent) {
        self.now = now
        self.clipboard = clipboard
        self.locale = locale
    }
}

public struct RenderedSnippet: Sendable, Equatable {
    public var text: String
    /// How many characters back from the end the caret should sit, if `{{cursor}}`
    /// was used. The inserter turns this into that many Left presses.
    public var cursorOffsetFromEnd: Int?
}

/// Parses `{{...}}` placeholders. Escape a literal brace pair with `\{{`.
///
/// Supported: `{{name}}`, `{{name:default}}`, `{{date}}`, `{{date:+3d}}`, `{{time}}`,
/// `{{clipboard}}`, `{{cursor}}`.
public struct SnippetTemplate: Sendable, Equatable {
    public let tokens: [SnippetToken]

    public init(tokens: [SnippetToken]) { self.tokens = tokens }

    public static let reservedNames: Set<String> = ["date", "time", "datetime", "clipboard", "cursor"]

    public var hasPlaceholders: Bool {
        tokens.contains { if case .literal = $0 { false } else { true } }
    }

    /// Fields needing user input, in first-appearance order, deduplicated.
    public var fields: [SnippetField] {
        var seen = Set<String>()
        var result: [SnippetField] = []
        for token in tokens {
            if case let .field(name, def) = token, !seen.contains(name) {
                seen.insert(name)
                result.append(SnippetField(name: name, defaultValue: def))
            }
        }
        return result
    }

    public var requiresInput: Bool { !fields.isEmpty }

    // MARK: - Parsing

    public static func parse(_ text: String) -> SnippetTemplate {
        var tokens: [SnippetToken] = []
        var literal = ""
        let chars = Array(text)
        var i = 0

        func flush() {
            if !literal.isEmpty { tokens.append(.literal(literal)); literal = "" }
        }

        while i < chars.count {
            // Escaped opener: \{{ emits a literal {{
            if chars[i] == "\\", i + 2 < chars.count, chars[i + 1] == "{", chars[i + 2] == "{" {
                literal.append("{{")
                i += 3
                continue
            }
            if chars[i] == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                // Find the closing }}
                var j = i + 2
                var body = ""
                var closed = false
                while j < chars.count {
                    if chars[j] == "}", j + 1 < chars.count, chars[j + 1] == "}" {
                        closed = true
                        break
                    }
                    body.append(chars[j])
                    j += 1
                }
                if closed, let token = makeToken(from: body) {
                    flush()
                    tokens.append(token)
                    i = j + 2
                    continue
                }
            }
            literal.append(chars[i])
            i += 1
        }
        flush()
        return SnippetTemplate(tokens: tokens)
    }

    private static func makeToken(from body: String) -> SnippetToken? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let name: String
        let argument: String?
        if let colon = trimmed.firstIndex(of: ":") {
            name = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            argument = String(trimmed[trimmed.index(after: colon)...])
        } else {
            name = trimmed
            argument = nil
        }
        guard !name.isEmpty else { return nil }

        switch name.lowercased() {
        case "cursor": return .cursor
        case "clipboard", "paste": return .clipboard
        case "time": return .time
        case "date", "datetime":
            return .date(offsetDays: argument.flatMap(parseDayOffset) ?? 0)
        default:
            let def = argument?.isEmpty == true ? nil : argument
            return .field(name: name, defaultValue: def)
        }
    }

    /// "+3d", "-1w", "+2m", "+1y" → a day offset.
    static func parseDayOffset(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        var sign = 1
        var rest = Substring(s)
        if rest.hasPrefix("+") { rest = rest.dropFirst() }
        else if rest.hasPrefix("-") { sign = -1; rest = rest.dropFirst() }

        let unit = rest.last
        let digits = (unit?.isNumber == true) ? rest : rest.dropLast()
        guard let n = Int(digits) else { return nil }

        let multiplier: Int
        switch unit {
        case "w": multiplier = 7
        case "m": multiplier = 30
        case "y": multiplier = 365
        default: multiplier = 1
        }
        return sign * n * multiplier
    }

    // MARK: - Rendering

    public func render(values: [String: String] = [:], context: RenderContext = RenderContext()) -> RenderedSnippet {
        var output = ""
        var cursorIndex: Int?

        for token in tokens {
            switch token {
            case .literal(let s):
                output += s
            case .field(let name, let def):
                let provided = values[name]?.isEmpty == false ? values[name] : nil
                output += provided ?? def ?? ""
            case .date(let offsetDays):
                let date = Calendar.current.date(byAdding: .day, value: offsetDays, to: context.now) ?? context.now
                output += date.formatted(.dateTime.day().month(.wide).year().locale(context.locale))
            case .time:
                output += context.now.formatted(.dateTime.hour().minute().locale(context.locale))
            case .clipboard:
                output += context.clipboard
            case .cursor:
                if cursorIndex == nil { cursorIndex = output.count }
            }
        }

        let offset = cursorIndex.map { output.count - $0 }
        return RenderedSnippet(text: output, cursorOffsetFromEnd: offset)
    }

    /// Convenience: does this text contain anything that needs filling in?
    public static func containsPlaceholders(_ text: String) -> Bool {
        parse(text).hasPlaceholders
    }

    public static func requiresInput(_ text: String) -> Bool {
        parse(text).requiresInput
    }
}
