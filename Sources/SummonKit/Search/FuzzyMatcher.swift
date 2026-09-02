import Foundation

/// Subsequence scoring in the style of fzy: consecutive runs, word boundaries and
/// prefixes all earn bonuses, and gaps are penalised. Returns matched character
/// positions so the UI can highlight exactly what matched.
///
/// Scoring runs against `Prepared` candidates — lowercased once when the index is
/// built rather than on every keystroke — and borrows its dynamic-programming tables
/// from a caller-owned `Scratch`. Allocating those per candidate was what made a
/// short query over a large library expensive: a one-character query is a subsequence
/// of nearly every title, so nearly every item paid for two fresh 2D arrays.
public enum FuzzyMatcher {

    public struct Match: Sendable, Equatable {
        public let score: Double
        /// Indices into the candidate string's character array.
        public let positions: [Int]
    }

    // Tuned so "prefix of a word" reliably beats "letters scattered through the middle".
    private static let gapLeading = -0.02
    private static let gapTrailing = -0.02
    private static let gapInner = -0.05
    private static let matchConsecutive = 1.0
    private static let matchWordStart = 0.9
    private static let matchSeparator = 0.85
    private static let matchCapital = 0.7
    private static let scoreMin = -Double.infinity
    static let maxCandidateLength = 512

    // MARK: - Prepared candidates

    /// A candidate string with the per-character work already done.
    public struct Prepared: Sendable, Equatable {
        /// One entry per `Character`, holding the first Unicode scalar of its
        /// lowercased form. Comparing integers rather than `Character` values is the
        /// difference that matters: a `Character` is a grapheme cluster backed by a
        /// String, so comparing them in the inner loop does Unicode work per cell.
        /// Keeping it one-per-character also keeps highlight positions aligned with
        /// `Array(text)`, and makes matching incidentally accent-insensitive.
        let lower: [UInt32]
        let bonuses: [Double]
        /// Too long to score with dynamic programming; falls back to containment.
        let isOversized: Bool
        let raw: String

        public init(_ text: String) {
            raw = text
            let chars = Array(text)
            if chars.count > maxCandidateLength {
                lower = []
                bonuses = []
                isOversized = true
            } else {
                lower = FuzzyMatcher.scalars(chars)
                bonuses = FuzzyMatcher.characterBonuses(chars)
                isOversized = false
            }
        }

        public var isEmpty: Bool { lower.isEmpty && !isOversized }
    }

    /// Reusable dynamic-programming storage, owned by one search pass.
    ///
    /// The tables stay as properties and are only ever touched inside a scoped
    /// `withUnsafeMutableBufferPointer`; handing a pointer back out would outlive
    /// the access it came from.
    public final class Scratch {
        private var d: [Double] = []
        private var m: [Double] = []

        public init() {}

        fileprivate func withTables<R>(
            _ size: Int,
            _ body: (UnsafeMutableBufferPointer<Double>, UnsafeMutableBufferPointer<Double>) -> R
        ) -> R {
            if d.count < size {
                // Grow generously so a long candidate does not reallocate repeatedly.
                let capacity = max(size, d.count * 2, 4096)
                d = [Double](repeating: 0, count: capacity)
                m = [Double](repeating: 0, count: capacity)
            }
            return d.withUnsafeMutableBufferPointer { db in
                m.withUnsafeMutableBufferPointer { mb in
                    body(db, mb)
                }
            }
        }
    }

    /// Lowercased scalar per character, so indices stay aligned with the original
    /// string. `String.lowercased()` can change the character count for some scripts,
    /// which would misplace the highlight positions.
    static func scalars(_ chars: [Character]) -> [UInt32] {
        chars.map { character in
            let lowered = character.isUppercase ? (character.lowercased().first ?? character) : character
            return lowered.unicodeScalars.first?.value ?? 0
        }
    }

    public static func scalars(_ text: String) -> [UInt32] { scalars(Array(text)) }

    // MARK: - Public matching

    public static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        isSubsequence(scalars(query), of: scalars(candidate))
    }

    static func isSubsequence(_ query: [UInt32], of candidate: [UInt32]) -> Bool {
        if query.isEmpty { return true }
        var qi = 0
        for character in candidate where character == query[qi] {
            qi += 1
            if qi == query.count { return true }
        }
        return false
    }

    /// Convenience for callers with plain strings — used by tests and one-off matches.
    public static func match(query: String, in candidate: String) -> Match? {
        match(query: scalars(query), in: Prepared(candidate), scratch: Scratch())
    }

    public static func match(
        query: [UInt32],
        in candidate: Prepared,
        scratch: Scratch,
        needsPositions: Bool = true
    ) -> Match? {
        guard !query.isEmpty else { return Match(score: 0, positions: []) }

        if candidate.isOversized {
            // Too long to score properly; fall back to a plain containment check.
            let needle = String(String.UnicodeScalarView(query.compactMap(Unicode.Scalar.init)))
            return candidate.raw.range(of: needle, options: [.caseInsensitive]) != nil
                ? Match(score: 0.2, positions: [])
                : nil
        }

        let c = candidate.lower
        let n = query.count, m = c.count
        guard m > 0, n <= m else { return nil }
        guard isSubsequence(query, of: c) else { return nil }

        // Exact, whole-string match short-circuits to the top.
        if n == m { return Match(score: 10, positions: Array(0..<m)) }

        let bonuses = candidate.bonuses
        return scratch.withTables(n * m) { D, M in
            score(query: query, c: c, n: n, m: m, bonuses: bonuses,
                  needsPositions: needsPositions, D: D, M: M)
        }
    }

    private static func score(
        query: [UInt32],
        c: [UInt32],
        n: Int,
        m: Int,
        bonuses: [Double],
        needsPositions: Bool,
        D: UnsafeMutableBufferPointer<Double>,
        M: UnsafeMutableBufferPointer<Double>
    ) -> Match? {
        for i in 0..<n {
            var prevScore = scoreMin
            let gapScore = (i == n - 1) ? gapTrailing : gapInner
            let row = i * m
            let prevRow = row - m

            for j in 0..<m {
                if query[i] == c[j] {
                    var score = scoreMin
                    if i == 0 {
                        score = Double(j) * gapLeading + bonuses[j]
                    } else if j > 0 {
                        let consecutive = D[prevRow + j - 1] + matchConsecutive
                        let fresh = M[prevRow + j - 1] + bonuses[j]
                        score = max(consecutive, fresh)
                    }
                    D[row + j] = score
                    prevScore = max(score, prevScore + gapScore)
                    M[row + j] = prevScore
                } else {
                    D[row + j] = scoreMin
                    prevScore += gapScore
                    M[row + j] = prevScore
                }
            }
        }

        let best = M[(n - 1) * m + (m - 1)]
        guard best > scoreMin else { return nil }

        // Normalise so long candidates do not outscore short ones purely by length.
        let normalised = best / (Double(n) + 0.15 * Double(m))

        // Ranking only needs the score. Positions are recomputed for the handful of
        // results that actually get shown, which saves an allocation per candidate.
        guard needsPositions else { return Match(score: normalised, positions: []) }

        // Backtrack for the matched positions.
        var positions = [Int](repeating: 0, count: n)
        var matchRequired = false
        var j = m - 1
        var i = n - 1
        while i >= 0 {
            let row = i * m
            let prevRow = row - m
            while j >= 0 {
                if D[row + j] != scoreMin && (matchRequired || D[row + j] == M[row + j]) {
                    matchRequired = i > 0 && j > 0 && M[row + j] == D[prevRow + j - 1] + matchConsecutive
                    positions[i] = j
                    j -= 1
                    break
                }
                j -= 1
            }
            i -= 1
        }

        return Match(score: normalised, positions: positions)
    }

    // MARK: - Bonuses

    static func characterBonuses(_ chars: [Character]) -> [Double] {
        var bonuses = [Double](repeating: 0, count: chars.count)
        var previous: Character = "/"
        for (i, ch) in chars.enumerated() {
            bonuses[i] = bonus(previous: previous, current: ch, isFirst: i == 0)
            previous = ch
        }
        return bonuses
    }

    private static func bonus(previous: Character, current: Character, isFirst: Bool) -> Double {
        if isFirst { return matchWordStart }
        if previous == " " || previous == "\n" || previous == "\t" { return matchWordStart }
        if previous == "-" || previous == "_" || previous == "/" { return matchSeparator }
        if previous == "." || previous == ":" || previous == "," { return matchSeparator * 0.8 }
        if previous.isLowercase && current.isUppercase { return matchCapital }
        if previous.isLetter == false && current.isLetter { return matchSeparator * 0.7 }
        return 0
    }
}
