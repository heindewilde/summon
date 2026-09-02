import Foundation
import FoundationModels
import Observation

public struct ItemSuggestion: Sendable, Equatable {
    public var title: String
    public var tags: [String]
    public var summary: String?
    public var cameFromModel: Bool

    public init(title: String, tags: [String] = [], summary: String? = nil, cameFromModel: Bool = false) {
        self.title = title
        self.tags = tags
        self.summary = summary
        self.cameFromModel = cameFromModel
    }
}

public enum IntelligenceStatus: Sendable, Equatable {
    case ready
    case disabled
    case unavailable(String)

    public var isReady: Bool { self == .ready }

    public var explanation: String {
        switch self {
        case .ready: "On-device model ready. Nothing leaves this Mac."
        case .disabled: "Turned off. Summon uses built-in rules instead."
        case .unavailable(let why): why
        }
    }
}

public enum RewriteTone: String, CaseIterable, Sendable {
    case moreFormal = "More formal"
    case moreCasual = "More casual"
    case shorter = "Shorter"
    case friendlier = "Friendlier"

    var instruction: String {
        switch self {
        case .moreFormal: "Rewrite it in a more formal, professional register."
        case .moreCasual: "Rewrite it in a warmer, more casual register."
        case .shorter: "Rewrite it to be significantly shorter while keeping every fact."
        case .friendlier: "Rewrite it to sound friendlier and more approachable."
        }
    }
}

// The model returns structured output rather than prose we would have to parse.
@Generable
struct GeneratedItemSuggestion {
    @Guide(description: "A short, specific title of at most six words. No quotation marks, no trailing period.")
    var title: String

    @Guide(description: "Two or three lowercase single-word keyword tags describing what this content is for.")
    var tags: [String]

    @Guide(description: "One plain sentence, at most twenty words, describing what this content is and when someone would reuse it.")
    var summary: String
}

/// The on-device intelligence layer.
///
/// Every call falls back to `Heuristics` — on failure, on timeout, on a Mac without
/// Apple Intelligence. Nothing here is ever load-bearing, and sensitive content is
/// never passed to the model even though the model is local.
@MainActor
@Observable
public final class Intelligence {
    public var isEnabled: Bool = true {
        didSet { refreshStatus() }
    }

    public private(set) var status: IntelligenceStatus = .disabled
    public private(set) var isWorking: Bool = false

    /// Anything slower than this is worse than the heuristic it would replace.
    private let timeout: Duration = .seconds(20)
    private let maxInputCharacters = 4_000

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        guard isEnabled else {
            status = .disabled
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            status = .ready
        case .unavailable(let reason):
            status = .unavailable(Intelligence.explain(reason))
        }
    }

    nonisolated static func explain(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This Mac doesn’t support Apple Intelligence, so Summon uses its built-in rules instead."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is turned off in System Settings. Summon is using its built-in rules."
        case .modelNotReady:
            "The on-device model is still downloading. Summon is using its built-in rules until it’s ready."
        @unknown default:
            "The on-device model isn’t available right now. Summon is using its built-in rules."
        }
    }

    // MARK: - Suggestions

    /// Title, tags and a summary for freshly imported content.
    ///
    /// `isSensitive` content skips the model entirely: the rule is that content the
    /// user marked secret is not handed to anything, local or not.
    public func suggest(
        forText text: String,
        kind: ItemKind,
        filename: String? = nil,
        isSensitive: Bool = false
    ) async -> ItemSuggestion {
        let fallback = ItemSuggestion(
            title: kind.isBlobBacked && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Heuristics.title(forFilename: filename ?? "Untitled")
                : Heuristics.title(forText: text),
            tags: Heuristics.tags(forText: text, kind: kind, filename: filename),
            summary: Heuristics.summary(forText: text),
            cameFromModel: false
        )

        guard status.isReady, !isSensitive else { return fallback }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 24 else { return fallback }

        isWorking = true
        defer { isWorking = false }

        let excerpt = String(trimmed.prefix(maxInputCharacters))
        let kindLabel = kind.displayName.lowercased()

        let generated: GeneratedItemSuggestion? = await run {
            let session = LanguageModelSession(instructions: """
            You label content for a personal snippet library. The user saves things \
            they reuse often: canned replies, documents they show clients, details \
            they paste into forms. Describe what the content is for, in the user's own \
            register. Never invent facts that are not in the content.
            """)
            let response = try await session.respond(
                to: """
                Here is a \(kindLabel) the user just saved\(filename.map { " (file name: \($0))" } ?? "").
                Produce a title, tags, and a one-sentence summary.

                ---
                \(excerpt)
                ---
                """,
                generating: GeneratedItemSuggestion.self,
                options: GenerationOptions(temperature: 0.3)
            )
            return response.content
        }

        guard let generated else { return fallback }

        let title = Intelligence.tidy(generated.title)
        let tags = generated.tags
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 24 }
        let summary = Intelligence.tidy(generated.summary)

        return ItemSuggestion(
            title: title.isEmpty ? fallback.title : title,
            // Union with the heuristic tags: the detectors catch things like an IBAN
            // that a language model has no special reason to notice.
            tags: Array(Array(Set(tags).union(fallback.tags)).sorted().prefix(5)),
            summary: summary.isEmpty ? fallback.summary : summary,
            cameFromModel: true
        )
    }

    // MARK: - Explicit user actions

    public func summarize(_ text: String) async -> String? {
        guard status.isReady else { return Heuristics.summary(forText: text) }
        isWorking = true
        defer { isWorking = false }

        let excerpt = String(text.prefix(maxInputCharacters))
        return await run {
            let session = LanguageModelSession(instructions:
                "You summarise documents plainly and briefly. No preamble, no bullet points.")
            let response = try await session.respond(
                to: "Summarise this in two sentences:\n\n\(excerpt)",
                options: GenerationOptions(temperature: 0.2)
            )
            return Intelligence.tidy(response.content)
        } ?? Heuristics.summary(forText: text)
    }

    /// Rewrites a snippet in a different register. Returns nil when unavailable, so
    /// the UI can hide the action rather than offer something that will not work.
    public func rewrite(_ text: String, tone: RewriteTone) async -> String? {
        guard status.isReady else { return nil }
        isWorking = true
        defer { isWorking = false }

        let excerpt = String(text.prefix(maxInputCharacters))
        return await run {
            let session = LanguageModelSession(instructions: """
            You rewrite short pieces of text the user reuses, such as email replies. \
            Preserve every placeholder written as {{like_this}} exactly, including its \
            braces. Return only the rewritten text, with no commentary.
            """)
            let response = try await session.respond(
                to: "\(tone.instruction)\n\n---\n\(excerpt)\n---",
                options: GenerationOptions(temperature: 0.6)
            )
            return Intelligence.tidy(response.content)
        }
    }

    // MARK: - Plumbing

    /// Runs an operation with a hard timeout, swallowing every failure into `nil`.
    private func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async -> T? {
        let limit = timeout
        return await withTaskGroup(of: T?.self, returning: T?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    nonisolated static func tidy(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Models like to wrap titles in quotes and end them with a full stop.
        if s.count > 1, s.hasPrefix("\""), s.hasSuffix("\"") { s = String(s.dropFirst().dropLast()) }
        while s.hasSuffix(".") && !s.hasSuffix("...") && s.split(separator: " ").count <= 8 {
            s = String(s.dropLast())
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
