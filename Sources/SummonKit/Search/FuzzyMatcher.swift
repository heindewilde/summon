import Foundation

/// Subsequence scoring in the style of fzy: consecutive runs, word boundaries and
/// prefixes all earn bonuses, and gaps are penalised. Returns matched character
/// positions so the UI can highlight exactly what matched.
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
    private static let maxCandidateLength = 512

    public static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        if query.isEmpty { return true }
        var qi = query.lowercased().startIndex
        let q = query.lowercased()
        for ch in candidate.lowercased() {
            if ch == q[qi] {
                qi = q.index(after: qi)
                if qi == q.endIndex { return true }
            }
        }
        return false
    }

    public static func match(query: String, in candidate: String) -> Match? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return Match(score: 0, positions: []) }

        let originalChars = Array(candidate)
        guard originalChars.count <= maxCandidateLength else {
            // Too long to score properly; fall back to a plain containment check.
            return candidate.range(of: query, options: [.caseInsensitive]) != nil
                ? Match(score: 0.2, positions: [])
                : nil
        }
        let c = Array(candidate.lowercased())
        guard !c.isEmpty, q.count <= c.count else { return nil }
        guard isSubsequence(query, of: candidate) else { return nil }

        // Exact, whole-string match short-circuits to the top.
        if q.count == c.count { return Match(score: 10, positions: Array(0..<c.count)) }

        let bonuses = characterBonuses(originalChars)

        let n = q.count, m = c.count
        // D: best score ending in a match at (i, j). M: best score overall at (i, j).
        var D = [[Double]](repeating: [Double](repeating: scoreMin, count: m), count: n)
        var M = D

        for i in 0..<n {
            var prevScore = scoreMin
            let gapScore = (i == n - 1) ? gapTrailing : gapInner

            for j in 0..<m {
                if q[i] == c[j] {
                    var score = scoreMin
                    if i == 0 {
                        score = Double(j) * gapLeading + bonuses[j]
                    } else if j > 0 {
                        let consecutive = D[i - 1][j - 1] + matchConsecutive
                        let fresh = M[i - 1][j - 1] + bonuses[j]
                        score = max(consecutive, fresh)
                    }
                    D[i][j] = score
                    prevScore = max(score, prevScore + gapScore)
                    M[i][j] = prevScore
                } else {
                    D[i][j] = scoreMin
                    prevScore = prevScore + gapScore
                    M[i][j] = prevScore
                }
            }
        }

        let best = M[n - 1][m - 1]
        guard best > scoreMin else { return nil }

        // Backtrack for the matched positions.
        var positions = [Int](repeating: 0, count: n)
        var matchRequired = false
        var j = m - 1
        var i = n - 1
        while i >= 0 {
            while j >= 0 {
                if D[i][j] != scoreMin && (matchRequired || D[i][j] == M[i][j]) {
                    matchRequired = i > 0 && j > 0 && M[i][j] == D[i - 1][j - 1] + matchConsecutive
                    positions[i] = j
                    j -= 1
                    break
                }
                j -= 1
            }
            i -= 1
        }

        // Normalise so long candidates do not outscore short ones purely by length.
        let normalised = best / (Double(n) + 0.15 * Double(m))
        return Match(score: normalised, positions: positions)
    }

    private static func characterBonuses(_ chars: [Character]) -> [Double] {
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
