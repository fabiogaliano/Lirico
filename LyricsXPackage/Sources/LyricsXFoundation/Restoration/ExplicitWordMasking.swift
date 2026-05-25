import Foundation

// MARK: - Mask characters

/// Characters treated as censorship masks.
///
/// Deliberately conservative: `*` and `#` are the only forms widely used to
/// blank out letters in lyric providers. `-` and `_` are excluded because they
/// appear inside ordinary hyphenated/underscored words and would create false
/// "censored token" matches. Leetspeak substitutions (`@`, `$`) are not masks —
/// they encode a specific letter rather than hiding one — so they are excluded.
let explicitMaskCharacters: Set<Character> = ["*", "#"]

func isMaskCharacter(_ character: Character) -> Bool {
    explicitMaskCharacters.contains(character)
}

private func isWordScalar(_ character: Character) -> Bool {
    character.isLetter || isMaskCharacter(character)
}

private func charactersCaseInsensitivelyEqual(_ lhs: Character, _ rhs: Character) -> Bool {
    lhs.lowercased() == rhs.lowercased()
}

// MARK: - Line segmentation

/// A line broken into word runs and the separators between them.
///
/// A `word` run is a maximal sequence of letters and/or mask characters, so a
/// censored token like `f**k` stays whole while the surrounding punctuation and
/// whitespace land in `separator` segments. Reassembling the segments in order
/// reproduces the original string exactly, which is what lets restoration swap a
/// single token without disturbing anything else on the line.
enum LineSegment: Equatable {
    case separator(String)
    case word(String)
}

func segmentLine(_ line: String) -> [LineSegment] {
    var segments: [LineSegment] = []
    var current = ""
    var currentIsWord: Bool?

    func flush() {
        guard let isWord = currentIsWord, !current.isEmpty else { return }
        segments.append(isWord ? .word(current) : .separator(current))
        current.removeAll(keepingCapacity: true)
    }

    for character in line {
        let isWord = isWordScalar(character)
        if currentIsWord != isWord {
            flush()
            currentIsWord = isWord
        }
        current.append(character)
    }
    flush()
    return segments
}

func reassemble(_ segments: [LineSegment]) -> String {
    segments.reduce(into: "") { result, segment in
        switch segment {
        case .separator(let text), .word(let text):
            result += text
        }
    }
}

/// A word run carries a mask only when it mixes at least one mask character with
/// the rest of its glyphs. A run of pure mask characters (`*****`) is still
/// "masked" — it just has no visible anchors for the lexicon to use.
func wordContainsMask(_ word: String) -> Bool {
    word.contains(where: isMaskCharacter)
}

func wordIsFullyMasked(_ word: String) -> Bool {
    wordContainsMask(word) && !word.contains(where: \.isLetter)
}

func lineContainsMaskedWord(_ line: String) -> Bool {
    segmentLine(line).contains { segment in
        if case .word(let word) = segment { return wordContainsMask(word) }
        return false
    }
}

/// Lowercased, letters-only form used for context comparison between lines.
/// Mask characters are dropped so an unmasked context word compares cleanly.
func normalizedWord(_ word: String) -> String {
    String(word.lowercased().filter { $0.isLetter })
}

// MARK: - Casing

/// The casing shape inferred from a masked token's visible letters, used to cast
/// a restored word back into the user-visible style (`f**k`→lower, `F**k`→title,
/// `F**K`→upper).
enum ExplicitCaseMode {
    case lower
    case title
    case upper
}

func caseMode(of token: [Character]) -> ExplicitCaseMode {
    let letters = token.filter(\.isLetter)
    guard !letters.isEmpty else { return .lower }

    let firstIsUpper = token.first.map { $0.isLetter && $0.isUppercase } ?? false

    if letters.allSatisfy(\.isUppercase) {
        // A lone uppercase letter is ambiguous between TITLE and UPPER; when it
        // is the leading glyph, treat it as title case ("F**k" patterns), which
        // is the far more common intent. Two or more uppercase visible letters
        // is an unambiguous all-caps shout.
        if letters.count >= 2 { return .upper }
        return firstIsUpper ? .title : .upper
    }
    return firstIsUpper ? .title : .lower
}

/// Restores a word at equal length, preserving the token's per-position casing
/// for visible letters and applying the inferred case mode to masked positions.
///
/// Precondition: `word.count == token.count`. Used for length-preserving masks
/// where every glyph index is meaningful (notably karaoke lines).
func restoredWordPreservingLength(word: String, token: [Character]) -> String {
    let wordCharacters = Array(word)
    let mode = caseMode(of: token)
    var output = ""
    output.reserveCapacity(wordCharacters.count)

    for index in wordCharacters.indices {
        let base = wordCharacters[index]
        let masked = token[index]
        if masked.isLetter {
            output += masked.isUppercase ? base.uppercased() : String(base)
        } else {
            switch mode {
            case .upper: output += base.uppercased()
            case .title: output += index == 0 ? base.uppercased() : String(base)
            case .lower: output += String(base)
            }
        }
    }
    return output
}

/// Restores a word whose length differs from the token, applying the inferred
/// case mode to the whole word (per-position mapping is meaningless here).
func restoredWordWholeCase(word: String, token: [Character]) -> String {
    switch caseMode(of: token) {
    case .upper: return word.uppercased()
    case .title: return word.prefix(1).uppercased() + word.dropFirst()
    case .lower: return word
    }
}

// MARK: - Single-token matching

private func isSubsequence(_ needle: [Character], of haystack: [Character]) -> Bool {
    var index = haystack.startIndex
    for character in needle {
        guard let next = haystack[index...].firstIndex(where: { charactersCaseInsensitivelyEqual($0, character) }) else {
            return false
        }
        index = haystack.index(after: next)
    }
    return true
}

/// Whether a masked `token` could be a length-preserving masking of `word`:
/// equal length, and every visible letter equals the word's letter at the same
/// index. e.g. `f**k`/`fuck`, `n****s`/`niggas`.
func tokenMatchesLengthPreserving(token: [Character], word: [Character]) -> Bool {
    guard token.count == word.count else { return false }
    for (tokenCharacter, wordCharacter) in zip(token, word) {
        if isMaskCharacter(tokenCharacter) { continue }
        guard tokenCharacter.isLetter,
              charactersCaseInsensitivelyEqual(tokenCharacter, wordCharacter) else {
            return false
        }
    }
    return true
}

/// Whether a masked `token` could be a length-changing masking of `word`,
/// judged purely by anchors: the first and last glyphs must be visible letters
/// matching the word's ends, and the visible letters must appear in order within
/// the word. e.g. `n*****s` (7) → `niggas` (6).
func tokenMatchesAnchored(token: [Character], word: [Character]) -> Bool {
    guard token.count != word.count else { return false }
    guard let tokenFirst = token.first, let tokenLast = token.last,
          let wordFirst = word.first, let wordLast = word.last else { return false }
    guard tokenFirst.isLetter, tokenLast.isLetter else { return false }
    guard charactersCaseInsensitivelyEqual(tokenFirst, wordFirst),
          charactersCaseInsensitivelyEqual(tokenLast, wordLast) else { return false }
    let visible = token.filter(\.isLetter)
    return isSubsequence(visible, of: word)
}

// MARK: - ExplicitLexicon

/// A curated set of uncensored words plus the deterministic logic to recognise
/// their masked forms.
///
/// Confidence comes from uniqueness: a masked token is only restored when it
/// matches exactly one lexicon word. A token with no visible letters (`*****`)
/// carries no textual evidence and is never restored here — those are left for
/// cross-candidate consensus.
public struct ExplicitLexicon: Sendable {
    public let words: [String]
    private let wordCharacters: [[Character]]

    public init(words: [String]) {
        var seen = Set<String>()
        var cleaned: [String] = []
        for raw in words {
            let normalized = String(raw.lowercased().filter { !$0.isWhitespace })
            guard !normalized.isEmpty,
                  normalized.allSatisfy(\.isLetter),
                  seen.insert(normalized).inserted else { continue }
            cleaned.append(normalized)
        }
        self.words = cleaned
        self.wordCharacters = cleaned.map(Array.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    /// Returns the confident restoration of a single masked token, or `nil` when
    /// the token is unmasked, fully masked, ambiguous, or unmatched.
    ///
    /// `lengthPreservingOnly` restricts to equal-length restorations, which is
    /// required on karaoke lines because the inline time-tag indices are glyph
    /// offsets into the displayed string.
    public func restore(token: String, lengthPreservingOnly: Bool) -> String? {
        let characters = Array(token)
        let maskCount = characters.lazy.filter(isMaskCharacter).count
        let visibleCount = characters.lazy.filter(\.isLetter).count
        guard maskCount > 0, visibleCount > 0 else { return nil }

        // Confidence gate: a single visible anchor is only trustworthy when very
        // little is hidden. Two-plus visible letters (e.g. f**k, n****s) is fine;
        // a lone anchor is accepted only when at most two glyphs are masked (a**),
        // which rejects deep single-anchor guesses like *****s → niggas.
        guard visibleCount >= 2 || maskCount <= 2 else { return nil }

        let lengthMatches = wordCharacters.filter {
            tokenMatchesLengthPreserving(token: characters, word: $0)
        }
        if lengthMatches.count == 1 {
            return restoredWordPreservingLength(word: String(lengthMatches[0]), token: characters)
        }
        if lengthMatches.count > 1 { return nil }

        guard !lengthPreservingOnly else { return nil }

        let anchoredMatches = wordCharacters.filter {
            tokenMatchesAnchored(token: characters, word: $0)
        }
        if anchoredMatches.count == 1 {
            return restoredWordWholeCase(word: String(anchoredMatches[0]), token: characters)
        }
        return nil
    }
}
