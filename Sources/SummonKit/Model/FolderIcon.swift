import Foundation

/// The symbols a folder can wear.
///
/// Curated rather than "all of SF Symbols": a picker with six thousand results is a
/// worse tool than one with a hundred good ones, and every symbol here is checked at
/// test time to actually resolve — a typo would otherwise ship as an empty square.
public enum FolderIcon {

    public struct Symbol: Sendable, Hashable, Identifiable {
        public let name: String
        /// Words people would search for that are not in the symbol's own name.
        public let keywords: [String]
        public var id: String { name }

        init(_ name: String, _ keywords: String = "") {
            self.name = name
            self.keywords = keywords.split(separator: " ").map(String.init)
        }
    }

    public struct Group: Sendable, Identifiable {
        public let title: String
        public let symbols: [Symbol]
        public var id: String { title }
    }

    public static let groups: [Group] = [
        Group(title: "Documents", symbols: [
            Symbol("folder"), Symbol("doc", "file page"), Symbol("doc.text", "writing"),
            Symbol("doc.richtext", "formatted"), Symbol("doc.on.doc", "copy duplicate"),
            Symbol("note.text", "notes"), Symbol("list.bullet", "list"),
            Symbol("list.bullet.rectangle", "form details"), Symbol("text.quote", "quote"),
            Symbol("signature", "sign contract"), Symbol("pencil", "edit write"),
            Symbol("book", "reading"), Symbol("newspaper", "press news"),
            Symbol("archivebox", "archive storage"), Symbol("tray", "inbox"),
            Symbol("paperclip", "attachment"),
        ]),
        Group(title: "Communication", symbols: [
            Symbol("envelope", "mail email reply"), Symbol("paperplane", "send"),
            Symbol("bubble.left", "chat comment"), Symbol("message", "sms chat"),
            Symbol("phone", "call"), Symbol("at", "email address handle"),
            Symbol("megaphone", "announce marketing"), Symbol("quote.bubble", "testimonial"),
        ]),
        Group(title: "Work", symbols: [
            Symbol("briefcase", "business work"), Symbol("building.2", "company office"),
            Symbol("building.columns", "bank legal"), Symbol("chart.bar", "stats report"),
            Symbol("chart.pie", "analytics"), Symbol("creditcard", "payment card"),
            Symbol("dollarsign.circle", "money price usd"),
            Symbol("eurosign.circle", "money price eur"),
            Symbol("percent", "tax vat discount"), Symbol("calendar", "date schedule"),
            Symbol("clock", "time hours"), Symbol("checkmark.seal", "verified approved"),
        ]),
        Group(title: "People", symbols: [
            Symbol("person", "contact"), Symbol("person.2", "team clients group"),
            Symbol("person.crop.circle", "profile avatar"), Symbol("hand.wave", "hello intro"),
            Symbol("graduationcap", "course teaching"), Symbol("heart", "favourite love"),
        ]),
        Group(title: "Media", symbols: [
            Symbol("photo", "image picture"), Symbol("camera", "photography"),
            Symbol("video", "film movie"), Symbol("music.note", "audio song"),
            Symbol("waveform", "audio sound"), Symbol("paintpalette", "brand design colour"),
            Symbol("paintbrush", "design art"), Symbol("wand.and.stars", "effects magic"),
            Symbol("theatermasks", "drama"), Symbol("mic", "podcast recording"),
        ]),
        Group(title: "Making", symbols: [
            Symbol("hammer", "build tools"), Symbol("wrench.and.screwdriver", "settings tools"),
            Symbol("terminal", "code shell"), Symbol("curlybraces", "code json"),
            Symbol("chevron.left.forwardslash.chevron.right", "code html"),
            Symbol("laptopcomputer", "mac computer"), Symbol("iphone", "mobile phone"),
            Symbol("keyboard", "typing shortcuts"), Symbol("cpu", "hardware"),
            Symbol("puzzlepiece", "plugin extension"),
        ]),
        Group(title: "Places", symbols: [
            Symbol("house", "home personal"), Symbol("building", "office"),
            Symbol("mappin", "location address"), Symbol("globe", "web world international"),
            Symbol("airplane", "travel trip"), Symbol("car", "drive vehicle"),
            Symbol("bag", "shopping"), Symbol("cart", "shop ecommerce"),
        ]),
        Group(title: "Marks", symbols: [
            Symbol("tag", "label"), Symbol("bookmark", "saved"), Symbol("pin", "pinned"),
            Symbol("star", "favourite important"), Symbol("flag", "flagged"),
            Symbol("lightbulb", "idea"), Symbol("sparkles", "new magic"),
            Symbol("bolt", "fast energy"), Symbol("flame", "hot urgent"),
            Symbol("leaf", "nature green"), Symbol("drop", "water"),
            Symbol("target", "goal focus"), Symbol("trophy", "win award"),
            Symbol("gift", "present"), Symbol("key", "access password"),
            Symbol("lock", "private secure"), Symbol("shield", "safety protection"),
            Symbol("exclamationmark.triangle", "warning careful"),
            Symbol("questionmark.circle", "help faq"), Symbol("info.circle", "information"),
        ]),
    ]

    public static let all: [Symbol] = groups.flatMap(\.symbols)

    /// The default a new folder gets. Nothing is guessed from the name, so this is
    /// what you see until you choose otherwise.
    public static let defaultSymbol = "folder"

    /// Matches on the symbol's name and its keywords, so "money" finds the currency
    /// symbols even though neither is called that.
    public static func search(_ query: String) -> [Symbol] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { symbol in
            symbol.name.lowercased().contains(needle)
                || symbol.keywords.contains { $0.hasPrefix(needle) }
        }
    }
}
