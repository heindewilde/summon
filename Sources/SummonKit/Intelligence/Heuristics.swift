import Foundation

/// The always-available floor beneath the on-device model.
///
/// Everything here is deterministic and runs on any Mac, so the app never depends on
/// Apple Intelligence being present — the model improves these results, it does not
/// enable them.
public enum Heuristics {

    private static let greetings = [
        "hi", "hey", "hello", "dear", "good morning", "good afternoon", "good evening",
        "hallo", "beste", "goedemorgen", "bonjour", "hola",
    ]

    private static let signOffs = [
        "best", "best regards", "kind regards", "regards", "thanks", "thank you",
        "cheers", "sincerely", "met vriendelijke groet", "groeten", "mvg",
    ]

    /// A short, human title for a block of text.
    public static func title(forText text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "Untitled snippet" }

        // A canned reply usually opens with a greeting, which says nothing about what
        // the snippet is for — so skip past it to the first line with real content.
        var candidate = lines[0]
        if isGreeting(candidate), lines.count > 1 {
            candidate = lines[1]
        }

        if let url = firstURL(in: candidate), candidate.count <= url.absoluteString.count + 4 {
            return titleForURL(url)
        }

        return truncate(candidate, to: 56)
    }

    /// Tags inferred from what the content plainly is.
    public static func tags(forText text: String, kind: ItemKind, filename: String? = nil) -> [String] {
        var tags = Set<String>()
        let lower = text.lowercased()

        if let filename, let ext = filename.split(separator: ".").last, ext.count <= 5 {
            if let t = tagForExtension(String(ext).lowercased()) { tags.insert(t) }
        }

        if detectors.email.firstMatch(in: text) { tags.insert("email") }
        if detectors.url.firstMatch(in: text) { tags.insert("link") }
        if detectors.iban.firstMatch(in: text) { tags.insert("banking") }
        if detectors.vat.firstMatch(in: text) { tags.insert("tax") }
        if detectors.phone.firstMatch(in: text) { tags.insert("contact") }
        if text.contains("```") || detectors.code.firstMatch(in: text) { tags.insert("code") }
        if SnippetTemplate.requiresInput(text) { tags.insert("template") }

        for (keyword, tag) in keywordTags where lower.contains(keyword) {
            tags.insert(tag)
        }

        if tags.isEmpty, kind.isTextual, looksLikeEmail(text) { tags.insert("email") }

        return Array(Array(tags).sorted().prefix(4))
    }

    /// One sentence describing the content, used when the model is unavailable.
    public static func summary(forText text: String) -> String? {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > 40 else { return nil }

        var sentence = ""
        flat.enumerateSubstrings(in: flat.startIndex..., options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            sentence = String(flat[range]).trimmingCharacters(in: .whitespaces)
            stop = true
        }
        if sentence.isEmpty { sentence = flat }
        return truncate(sentence, to: 140)
    }

    /// A file's title, cleaned up from its name: "acme_proposal-v3 FINAL.pdf" → "Acme proposal v3 FINAL".
    public static func title(forFilename filename: String) -> String {
        var base = (filename as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: "_", with: " ")
        base = base.replacingOccurrences(of: "-", with: " ")
        base = base.replacingOccurrences(of: "  ", with: " ")
        base = base.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return filename }
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    // MARK: - Internals

    static func isGreeting(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        // Short line that opens with a greeting word, e.g. "Hi {{first_name}},"
        guard lower.count <= 60 else { return false }
        return greetings.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + ",") }
    }

    static func isSignOff(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        return signOffs.contains(lower)
    }

    static func looksLikeEmail(_ text: String) -> Bool {
        let lines = text.split(separator: "\n").map { clean(String($0)) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        return isGreeting(lines[0]) || lines.contains(where: isSignOff)
    }

    private static func clean(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while let first = s.first, "#>-*•\t".contains(first) {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    private static func truncate(_ s: String, to limit: Int) -> String {
        guard s.count > limit else { return s }
        let cut = s.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private static func titleForURL(_ url: URL) -> String {
        let host = (url.host() ?? "link").replacingOccurrences(of: "www.", with: "")
        let path = url.pathComponents.filter { $0 != "/" }.last
        if let path, !path.isEmpty, path.count < 40 {
            return "\(host) · \(path.replacingOccurrences(of: "-", with: " "))"
        }
        return host
    }

    private static func tagForExtension(_ ext: String) -> String? {
        switch ext {
        case "pdf": "pdf"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff": "image"
        case "doc", "docx", "pages", "rtf", "txt", "md": "document"
        case "xls", "xlsx", "numbers", "csv": "spreadsheet"
        case "ppt", "pptx", "key": "presentation"
        case "zip", "dmg", "pkg": "archive"
        case "mov", "mp4", "m4v": "video"
        case "sketch", "fig", "psd", "ai", "svg": "design"
        default: nil
        }
    }

    private static let keywordTags: [(String, String)] = [
        ("invoice", "invoice"), ("factuur", "invoice"),
        ("contract", "legal"), ("agreement", "legal"), ("nda", "legal"),
        ("proposal", "sales"), ("quote", "sales"), ("offerte", "sales"),
        ("onboarding", "onboarding"),
        ("meeting", "meetings"), ("agenda", "meetings"),
        ("password", "credentials"), ("api key", "credentials"),
        ("passport", "identity"), ("bsn", "identity"),
        ("address", "contact"),
    ]

    private struct Detectors {
        let email = Regex1(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#)
        let url = Regex1(#"https?://[^\s]+"#)
        let iban = Regex1(#"\b[A-Z]{2}[0-9]{2}[ ]?[A-Z0-9]{4}([ ]?[0-9]{4}){2,4}\b"#)
        let vat = Regex1(#"\b[A-Z]{2}[0-9]{8,12}B?[0-9]{0,2}\b"#)
        let phone = Regex1(#"(\+[0-9]{1,3}[ -]?)?(\([0-9]{1,4}\)[ -]?)?[0-9][0-9 \-]{6,}[0-9]"#)
        let code = Regex1(#"(func |function |const |let |var |class |import |def |#include|=> |\{\s*\n)"#)
    }

    private static let detectors = Detectors()

    /// A tiny case-insensitive regex wrapper, so the detector table above stays readable.
    struct Detector: Sendable {}

    struct Regex1: Sendable {
        private let regex: NSRegularExpression?
        init(_ pattern: String) {
            regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        func firstMatch(in text: String) -> Bool {
            guard let regex else { return false }
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }
}
