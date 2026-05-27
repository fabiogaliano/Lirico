import Testing
@testable import LiricoFoundation

// MARK: - Helpers

private let seedWords = ["shit", "fuck", "bitch", "asshole", "nigga", "niggas"]

private func restorer(_ words: [String] = seedWords) -> ExplicitWordRestorer {
    ExplicitWordRestorer(words: words)
}

private func restore(
    _ line: String,
    words: [String] = seedWords,
    timed: Bool = false,
    alternates: [String] = []
) -> String {
    restorer(words).restoreLine(
        line,
        lengthPreservingOnly: timed,
        alternateLineSets: alternates.map { [$0] }
    )
}

// MARK: - Lexicon: case-preserving restoration

@Test func restoresLowercaseMask() {
    #expect(restore("f**k") == "fuck")
    #expect(restore("s**t") == "shit")
    #expect(restore("sh*t") == "shit")
}

@Test func preservesTitleCase() {
    #expect(restore("F**k") == "Fuck")
    #expect(restore("S**t") == "Shit")
}

@Test func preservesAllCaps() {
    #expect(restore("F**K") == "FUCK")
    #expect(restore("B***H") == "BITCH")
}

@Test func restoresLengthPreservingPluralMask() {
    #expect(restore("n****s") == "niggas")
    #expect(restore("N****s") == "Niggas")
}

// MARK: - Lexicon: word-boundary safety

@Test func onlyReplacesTheMaskedToken() {
    #expect(restore("duck f**k") == "duck fuck")
    #expect(restore("all my n****s here") == "all my niggas here")
}

@Test func preservesSurroundingPunctuation() {
    #expect(restore("f**k!") == "fuck!")
    #expect(restore("F**k, really") == "Fuck, really")
}

@Test func leavesUnmaskedTextUntouched() {
    // The feature restores masked words; it never censors or rewrites clean text.
    #expect(restore("shit happens") == "shit happens")
    #expect(restore("all my friends") == "all my friends")
}

@Test func doesNotMatchUnrelatedMaskedWord() {
    // "unf**k" has a mask but matches no lexicon word at its length → untouched.
    #expect(restore("unf**k it") == "unf**k it")
}

// MARK: - Lexicon: ambiguity & confidence

@Test func ambiguousLengthMaskLeftUnchanged() {
    // Both candidates fit "sh*t" at equal length → no confident restoration.
    #expect(restore("sh*t", words: ["shit", "shot"]) == "sh*t")
}

@Test func fullyMaskedTokenNotRestoredByLexiconAlone() {
    // No visible letters → no textual evidence → lexicon never guesses.
    #expect(restore("*****") == "*****")
    #expect(restore("you a *****") == "you a *****")
}

@Test func noLexiconAndNoAlternatesReturnsInput() {
    #expect(restore("f**k", words: []) == "f**k")
}

@Test func singleAnchorWithDeepMaskIsNotGuessed() {
    // Only "s" is visible under five masks — too little evidence to map to niggas.
    #expect(restore("*****s", words: ["niggas"]) == "*****s")
    // Even a unique length match must clear the confidence gate.
    #expect(restore("n*****", words: ["niggas"]) == "n*****")
}

@Test func singleAnchorWithShallowMaskIsAllowed() {
    // One visible letter is acceptable when at most two glyphs are hidden.
    #expect(restore("a**", words: ["ass"]) == "ass")
    #expect(restore("a*s", words: ["ass"]) == "ass")
}

// MARK: - Lexicon: karaoke length guard

@Test func lengthChangingMaskAllowedOnlyWhenUntimed() {
    // "n*****s" (7) → "niggas" (6) changes length: fine for line-synced, but a
    // karaoke line must keep its glyph count for the time-tag indices.
    #expect(restore("n*****s", timed: false) == "niggas")
    #expect(restore("n*****s", timed: true) == "n*****s")
}

@Test func lengthPreservingMaskStillRestoredWhenTimed() {
    #expect(restore("f**k", timed: true) == "fuck")
    #expect(restore("n****s", timed: true) == "niggas")
}

// MARK: - Cross-candidate consensus

@Test func restoresFullyMaskedTokenFromStrongAlternate() {
    #expect(
        restore("all my ***** with me", words: [], alternates: ["all my niggas with me"])
            == "all my niggas with me"
    )
}

@Test func restoresEndOfLineMaskFromAlternate() {
    #expect(
        restore("you a *****", words: [], alternates: ["you a bitch"]) == "you a bitch"
    )
}

@Test func crossCandidateRespectsTokenCasing() {
    #expect(
        restore("You a *****", words: [], alternates: ["you a bitch"]) == "You a bitch"
    )
}

@Test func leavesMaskWhenAlternateIsMisaligned() {
    #expect(
        restore("all my ***** with me", words: [], alternates: ["a completely unrelated phrase"])
            == "all my ***** with me"
    )
}

@Test func fullyMaskedOneSidedContextNeedsMoreThanOneAnchor() {
    #expect(
        restore("fuck *****", words: [], alternates: ["fuck around and find out"])
            == "fuck *****"
    )
    #expect(
        restore("***** fuck", words: [], alternates: ["around and find out fuck"])
            == "***** fuck"
    )
}

@Test func fullyMaskedOneSidedContextMustStayAtLineBoundary() {
    #expect(
        restore("you a *****", words: [], alternates: ["you a bitch right now"])
            == "you a *****"
    )
    #expect(
        restore("***** with me", words: [], alternates: ["all niggas with me"])
            == "***** with me"
    )
}

@Test func leavesMaskWhenAlternatesConflict() {
    let result = restorer([]).restoreLine(
        "you a *****",
        lengthPreservingOnly: false,
        alternateLineSets: [["you a bitch"], ["you a queen"]]
    )
    #expect(result == "you a *****")
}

@Test func crossCandidateLengthChangeBlockedOnTimedLine() {
    // 5-glyph mask → 6-glyph word would shift karaoke timing: blocked when timed.
    #expect(
        restore("all my ***** with me", words: [], timed: true, alternates: ["all my niggas with me"])
            == "all my ***** with me"
    )
}

@Test func crossCandidateEqualLengthAllowedOnTimedLine() {
    #expect(
        restore("you a *****", words: [], timed: true, alternates: ["you a bitch"]) == "you a bitch"
    )
}

@Test func lexiconTakesPrecedenceOverAlternates() {
    // A confident lexicon hit should win without needing alternate evidence.
    #expect(restore("f**k", alternates: ["totally different line"]) == "fuck")
}
