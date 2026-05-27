import Foundation

// MARK: - ExplicitWordRestorer

/// Restores censored words in a single display line using two ordered strategies:
///
/// 1. A deterministic lexicon pass — highest confidence, no evidence required.
/// 2. A cross-candidate consensus pass — repairs the tokens the lexicon could not
///    resolve (notably fully-masked spans) using aligned words from alternate
///    fetched lyrics for the same song.
///
/// The restorer is pure and stateless: callers supply the lexicon words and the
/// alternate line texts. `lengthPreservingOnly` is set by the caller for karaoke
/// (word-timed) lines, where the displayed glyph count must not change or the
/// per-word highlight desyncs.
public struct ExplicitWordRestorer: Sendable {
    private let lexicon: ExplicitLexicon

    public init(words: [String]) {
        self.lexicon = ExplicitLexicon(words: words)
    }

    public init(lexicon: ExplicitLexicon) {
        self.lexicon = lexicon
    }

    /// Whether this restorer can do anything at all. Used by the app layer to
    /// skip building per-line restorers when the feature is effectively off.
    public func canRestore(hasAlternates: Bool) -> Bool {
        !lexicon.isEmpty || hasAlternates
    }

    public func restoreLine(
        _ line: String,
        lengthPreservingOnly: Bool,
        alternateLineSets: [[String]] = []
    ) -> String {
        guard lineContainsMaskedWord(line) else { return line }

        let afterLexicon = restoreLexiconOnly(line, lengthPreservingOnly: lengthPreservingOnly)

        guard !alternateLineSets.isEmpty, lineContainsMaskedWord(afterLexicon) else {
            return afterLexicon
        }
        return applyCrossCandidatePass(
            afterLexicon,
            lengthPreservingOnly: lengthPreservingOnly,
            alternateLineSets: alternateLineSets
        )
    }

    /// Applies only the deterministic lexicon pass.
    public func restoreLexiconOnly(_ line: String, lengthPreservingOnly: Bool) -> String {
        applyLexiconPass(line, lengthPreservingOnly: lengthPreservingOnly)
    }

    // MARK: - Lexicon pass

    private func applyLexiconPass(_ line: String, lengthPreservingOnly: Bool) -> String {
        guard !lexicon.isEmpty else { return line }
        let segments = segmentLine(line).map { segment -> LineSegment in
            guard case .word(let word) = segment, wordContainsMask(word) else { return segment }
            if let restored = lexicon.restore(token: word, lengthPreservingOnly: lengthPreservingOnly) {
                return .word(restored)
            }
            return segment
        }
        return reassemble(segments)
    }

    // MARK: - Cross-candidate pass

    private func applyCrossCandidatePass(
        _ line: String,
        lengthPreservingOnly: Bool,
        alternateLineSets: [[String]]
    ) -> String {
        var segments = segmentLine(line)

        // Positions of word segments and their text, in reading order.
        let wordSlots: [(segmentIndex: Int, text: String)] = segments.enumerated().compactMap { index, segment in
            guard case .word(let word) = segment else { return nil }
            return (index, word)
        }
        let words = wordSlots.map(\.text)

        // The unmasked words on this line form the context fingerprint used to
        // locate the matching line in each alternate candidate.
        let contextWords = words.compactMap { word -> String? in
            guard !wordContainsMask(word) else { return nil }
            let normalized = normalizedWord(word)
            return normalized.isEmpty ? nil : normalized
        }

        // Choose, per alternate candidate, the line most likely to be the same
        // lyric line. A weak match contributes no evidence.
        let counterpartWordLists: [[String]] = alternateLineSets.compactMap { altLines in
            bestCounterpartWords(for: contextWords, in: altLines)
        }
        guard !counterpartWordLists.isEmpty else { return line }

        for (slotIndex, slot) in wordSlots.enumerated() {
            guard wordContainsMask(slot.text) else { continue }

            let leftContext = nearestUnmaskedContext(in: words, before: slotIndex)
            let rightContext = nearestUnmaskedContext(in: words, after: slotIndex)

            // A masked token with no surrounding unmasked anchor cannot be aligned.
            guard leftContext != nil || rightContext != nil else { continue }

            let isFullyMasked = wordIsFullyMasked(slot.text)
            let hasOneSidedContext = (leftContext == nil) != (rightContext == nil)
            // A fully-masked token with only one surrounding anchor needs at least
            // two visible context words on the line; one anchor alone (`fuck *****`)
            // is too weak and drifts into arbitrary next/previous-word guesses.
            if isFullyMasked, hasOneSidedContext, contextWords.count < 2 {
                continue
            }

            let proposals = counterpartWordLists.compactMap { altWords in
                alignedFill(
                    in: altWords,
                    leftContext: leftContext,
                    rightContext: rightContext,
                    maskedToken: slot.text,
                    lengthPreservingOnly: lengthPreservingOnly
                )
            }

            // Consensus: every alternate that produced a fill must agree on the
            // same word. A conflict is treated as ambiguous and left censored.
            let distinct = Set(proposals)
            guard distinct.count == 1, let consensus = distinct.first else { continue }

            let tokenCharacters = Array(slot.text)
            let restored = tokenCharacters.count == consensus.count
                ? restoredWordPreservingLength(word: consensus, token: tokenCharacters)
                : restoredWordWholeCase(word: consensus, token: tokenCharacters)
            segments[slot.segmentIndex] = .word(restored)
        }

        return reassemble(segments)
    }
}

// MARK: - Cross-candidate helpers

private struct ContextWord {
    let normalized: String
}

private func nearestUnmaskedContext(in words: [String], before index: Int) -> ContextWord? {
    var cursor = index - 1
    while cursor >= 0 {
        let word = words[cursor]
        if !wordContainsMask(word) {
            let normalized = normalizedWord(word)
            if !normalized.isEmpty { return ContextWord(normalized: normalized) }
        }
        cursor -= 1
    }
    return nil
}

private func nearestUnmaskedContext(in words: [String], after index: Int) -> ContextWord? {
    var cursor = index + 1
    while cursor < words.count {
        let word = words[cursor]
        if !wordContainsMask(word) {
            let normalized = normalizedWord(word)
            if !normalized.isEmpty { return ContextWord(normalized: normalized) }
        }
        cursor += 1
    }
    return nil
}

/// Picks the alternate line whose unmasked words best overlap this line's
/// context, returning its word runs. Requires a majority overlap so unrelated
/// lines (or a different verse) contribute no false evidence.
private func bestCounterpartWords(
    for contextWords: [String],
    in altLines: [String]
) -> [String]? {
    guard !contextWords.isEmpty else { return nil }

    var best: (score: Double, shared: Int, words: [String])?
    for altLine in altLines {
        let altWords = segmentLine(altLine).compactMap { segment -> String? in
            guard case .word(let word) = segment else { return nil }
            return word
        }
        let altNormalizedSet = Set(altWords.filter { !wordContainsMask($0) }.map(normalizedWord))
        let shared = contextWords.filter { altNormalizedSet.contains($0) }.count
        guard shared >= 1 else { continue }
        let score = Double(shared) / Double(contextWords.count)
        if score >= 0.5, best == nil || shared > best!.shared || (shared == best!.shared && score > best!.score) {
            best = (score, shared, altWords)
        }
    }
    return best?.words
}

/// Extracts the single unmasked word that sits between the same left/right
/// context in an alternate line, returning its normalized form when it is a
/// consistent fill for the masked token.
private func alignedFill(
    in altWords: [String],
    leftContext: ContextWord?,
    rightContext: ContextWord?,
    maskedToken: String,
    lengthPreservingOnly: Bool
) -> String? {
    let normalized = altWords.map { wordContainsMask($0) ? "" : normalizedWord($0) }

    func fillCandidate() -> (index: Int, word: String)? {
        switch (leftContext, rightContext) {
        case let (.some(left), .some(right)):
            guard let leftIndex = normalized.firstIndex(of: left.normalized) else { return nil }
            guard let rightIndex = normalized[(leftIndex + 1)...].firstIndex(of: right.normalized) else { return nil }
            // Exactly one word between the anchors keeps the alignment unambiguous.
            guard rightIndex - leftIndex == 2,
                  let word = wordAt(leftIndex + 1, in: altWords) else { return nil }
            return (leftIndex + 1, word)
        case let (.some(left), .none):
            guard let leftIndex = normalized.firstIndex(of: left.normalized),
                  let word = wordAt(leftIndex + 1, in: altWords) else { return nil }
            return (leftIndex + 1, word)
        case let (.none, .some(right)):
            guard let rightIndex = normalized.firstIndex(of: right.normalized),
                  let word = wordAt(rightIndex - 1, in: altWords) else { return nil }
            return (rightIndex - 1, word)
        case (.none, .none):
            return nil
        }
    }

    guard let candidate = fillCandidate(),
          !wordContainsMask(candidate.word) else { return nil }

    if wordIsFullyMasked(maskedToken) {
        switch (leftContext, rightContext) {
        case (.some, .none):
            guard candidate.index == altWords.index(before: altWords.endIndex) else { return nil }
        case (.none, .some):
            guard candidate.index == altWords.startIndex else { return nil }
        case (.some, .some), (.none, .none):
            break
        }
    }

    guard isConsistentFill(
        replacement: candidate.word,
        maskedToken: maskedToken,
        lengthPreservingOnly: lengthPreservingOnly
    ) else { return nil }

    return normalizedWord(candidate.word)
}

private func wordAt(_ index: Int, in words: [String]) -> String? {
    words.indices.contains(index) ? words[index] : nil
}

/// Whether an unmasked `replacement` is a plausible fill for `maskedToken`:
/// its visible anchors must agree, and on karaoke lines the length must match.
private func isConsistentFill(
    replacement: String,
    maskedToken: String,
    lengthPreservingOnly: Bool
) -> Bool {
    let tokenCharacters = Array(maskedToken)
    let replacementCharacters = Array(replacement)

    if lengthPreservingOnly, tokenCharacters.count != replacementCharacters.count {
        return false
    }

    let hasVisibleLetters = tokenCharacters.contains(where: \.isLetter)
    if hasVisibleLetters {
        if tokenCharacters.count == replacementCharacters.count {
            return tokenMatchesLengthPreserving(token: tokenCharacters, word: replacementCharacters)
        }
        return tokenMatchesAnchored(token: tokenCharacters, word: replacementCharacters)
    }
    // Fully-masked token: rely on the surrounding context match already proven
    // by the caller; any unmasked, length-consistent word is accepted.
    return true
}
