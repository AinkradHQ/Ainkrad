import Foundation

/// Fuzzy matching with a relevance SCORE.
///
/// The host already has `fuzzyMatches(query:target:)` in `Core/Launcher` — a
/// boolean subsequence test — and this reuses it for the accept/reject
/// decision rather than reimplementing it. What it adds is ranking: the
/// launcher shows a handful of apps where any order is fine, while ⌘P over a
/// whole tree returns hundreds of candidates and is only usable if the best
/// one is first.
///
/// Also distinct from `matchesSearch`, which is a plain substring test. Fuzzy
/// matching is right where the user is *jumping* to something they already have
/// in mind (⌘P, `/`) and surprise is acceptable; it is wrong for a recursive
/// file search, where unpredictable matches read as a broken tool.
///
/// Scoring rewards, in order: a prefix match, matches after a separator
/// (word starts), and consecutive runs. That ordering is what makes "fkv"
/// find "FileListView.swift" ahead of a file that merely contains those
/// letters scattered.
struct FuzzyResult: Equatable {
    var score: Int
    /// Indices of matched characters, for highlighting.
    var matchedIndices: [Int]
}

func fuzzyScore(_ candidate: String, pattern: String) -> FuzzyResult? {
    guard !pattern.isEmpty else { return FuzzyResult(score: 0, matchedIndices: []) }
    // Accept/reject is the host's existing matcher; only the scoring below is
    // new. Keeping one definition of "does this match" means the launcher and
    // the file jumper can never disagree about it.
    guard fuzzyMatches(query: pattern, target: candidate) else { return nil }

    let candidateChars = Array(candidate.lowercased())
    let patternChars = Array(pattern.lowercased())

    var score = 0
    var matched: [Int] = []
    var candidateIndex = 0
    var previousMatchIndex = -1

    for patternChar in patternChars {
        var found = false
        while candidateIndex < candidateChars.count {
            if candidateChars[candidateIndex] == patternChar {
                matched.append(candidateIndex)

                if candidateIndex == 0 {
                    score += 15  // matches the very start
                } else if isSeparator(candidateChars[candidateIndex - 1]) {
                    score += 10  // start of a word
                } else if isUppercaseBoundary(candidate, at: candidateIndex) {
                    score += 8  // camelCase hump
                }

                if candidateIndex == previousMatchIndex + 1 {
                    score += 5  // consecutive run
                }
                // Later matches are weaker: a hit at the end of a long name is
                // less likely to be what was meant.
                score -= candidateIndex / 8

                previousMatchIndex = candidateIndex
                candidateIndex += 1
                found = true
                break
            }
            candidateIndex += 1
        }
        guard found else { return nil }
    }

    // Shorter candidates win ties — "main.swift" beats "domain-mapper.swift"
    // for "main".
    score -= candidateChars.count / 12
    return FuzzyResult(score: score, matchedIndices: matched)
}

private func isSeparator(_ character: Character) -> Bool {
    character == "/" || character == "_" || character == "-"
        || character == "." || character == " "
}

private func isUppercaseBoundary(_ text: String, at index: Int) -> Bool {
    let characters = Array(text)
    guard index > 0, index < characters.count else { return false }
    return characters[index].isUppercase && characters[index - 1].isLowercase
}

/// Ranks `candidates` against `pattern`, best first, dropping non-matches.
func fuzzyRank<T>(
    _ candidates: [T], pattern: String,
    name: (T) -> String
) -> [(item: T, result: FuzzyResult)] {
    guard !pattern.isEmpty else { return candidates.map { ($0, FuzzyResult(score: 0, matchedIndices: [])) } }
    return
        candidates
        .compactMap { candidate -> (item: T, result: FuzzyResult)? in
            guard let result = fuzzyScore(name(candidate), pattern: pattern) else { return nil }
            return (candidate, result)
        }
        // Stable within equal scores, so results don't jitter as you type.
        .enumerated()
        .sorted { ($0.element.result.score, -$0.offset) > ($1.element.result.score, -$1.offset) }
        .map(\.element)
}
