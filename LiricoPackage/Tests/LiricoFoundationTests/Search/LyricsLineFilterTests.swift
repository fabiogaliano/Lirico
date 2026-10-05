import Foundation
import Testing
@testable import LiricoFoundation

/// The lines of `body` left enabled after filtering with `keys`.
private func keptLines(_ body: [String], keys: [String], enabled: Bool = true) -> [String] {
    let lrc = body.enumerated().map { String(format: "[00:%02d.000]", $0.offset) + $0.element }.joined(separator: "\n")
    let lyrics = Lyrics(lrc)!
    lyrics.filtrate(isIncluded: makeLyricsFilterPredicate(keys: keys, enabled: enabled))
    return lyrics.lines.filter(\.enabled).map(\.content)
}

@Suite("Lyrics line filter")
struct LyricsLineFilterTests {
    @Test func plainKeysMatchLiterallyAnywhereInTheLine() {
        let kept = keptLines(["作词 : someone", "a.b c", "axb", "hello"], keys: ["作词", "a.b"])
        #expect(kept == ["axb", "hello"])
    }

    @Test func slashPrefixedKeysAreRegularExpressions() {
        let kept = keptLines(["123", "123 go", "axb"], keys: [#"/^\d+$"#, "/a.b"])
        #expect(kept == ["123 go"])
    }

    @Test func matchingIsCaseSensitive() {
        let kept = keptLines(["Lyrics by someone", "lyrics by someone"], keys: ["Lyrics"])
        #expect(kept == ["lyrics by someone"])
    }

    @Test func anInvalidRegularExpressionIsIgnoredAndTheOtherKeysStillApply() {
        let kept = keptLines(["(hello", "作词 : someone"], keys: ["/(", "作词"])
        #expect(kept == ["(hello"])
    }

    @Test func aDisabledFilterKeepsEveryLine() {
        let kept = keptLines(["作词 : someone", "hello"], keys: ["作词"], enabled: false)
        #expect(kept == ["作词 : someone", "hello"])
    }
}
