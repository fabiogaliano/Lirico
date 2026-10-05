import Testing
import Foundation
@testable import LiricoFoundation

@Suite("Decorated Query Titles")
struct DecoratedQueryTitleTests {
    @Test("Player-decorated titles match the plain candidate title strongly", arguments: [
        ("Wonderwall (2014 Remaster)", "Wonderwall"),
        ("Wonderwall - Remastered 2011", "Wonderwall"),
        ("Song - Single Version", "Song"),
        ("Song (Sped Up)", "Song"),
        ("Love Story (Taylor's Version)", "Love Story"),
        ("Let It Go (From \"Frozen\")", "Let It Go"),
        ("Song - From the Motion Picture Soundtrack", "Song"),
        ("Song (feat. Someone) [2011 Remaster]", "Song"),
        ("Song [Deluxe Edition]", "Song"),
    ])
    func decoratedQueryMatchesPlainCandidate(query: String, candidate: String) {
        #expect(titleMatchLevel(query: query, candidate: candidate) == .strong)
        #expect(titleMatchLevel(query: candidate, candidate: query) == .strong)
    }

    @Test("Undecorated parentheticals are part of the title, not stripped")
    func meaningfulParentheticalKept() {
        #expect(titleMatchLevel(query: "Song (Part II)", candidate: "Song") != .strong)
        #expect(titleMatchLevel(query: "Song (Part II)", candidate: "Song") != .exact)
    }

    @Test("Reprises, intros, outros and interludes are different recordings, not decorations", arguments: [
        ("Lover (Reprise)", "Lover"),
        ("Lover - Reprise", "Lover"),
        ("Song (Reprise / Remastered 2011)", "Song"),
        ("Song (Intro Version)", "Song"),
        ("Love Intro", "Love Interlude"),
        ("Song (Outro)", "Song"),
    ])
    func distinctRecordingsStayApart(query: String, candidate: String) {
        for (q, c) in [(query, candidate), (candidate, query)] {
            let level = titleMatchLevel(query: q, candidate: c)
            #expect(level != .strong && level != .exact, "\(q) vs \(c) was \(level)")
        }
    }

    @Test("Decoration around a reprise is still stripped")
    func decoratedReprise() {
        #expect(titleMatchLevel(query: "Lover (Reprise) [2019 Remaster]", candidate: "Lover (Reprise)") == .strong)
        #expect(titleMatchLevel(query: "Lover (Reprise)", candidate: "Lover (Reprise) - Live") == .strong)
    }

    @Test("Decoration words inside the title proper are part of the name", arguments: [
        ("Video Killed the Radio Star", "Video Killed the Radio"),
        ("lacy", "lacy acoustic"),
    ])
    func unseparatedWordsAreNotDecoration(query: String, candidate: String) {
        for (q, c) in [(query, candidate), (candidate, query)] {
            let level = titleMatchLevel(query: q, candidate: c)
            #expect(level != .strong && level != .exact, "\(q) vs \(c) was \(level)")
        }
    }

    @Test("A reprise found on its own is only a loose fallback for the song it reprises")
    func repriseIsLooseFallback() {
        let lyrics = Lyrics("[ti:Lover (Reprise)]\n[ar:Taylor Swift]\n[00:01.000]line one\n[00:05.000]line two")!
        let e = LyricsCandidateEvaluator().evaluate(
            lyrics: lyrics,
            mode: .titleAndArtist(title: "Lover", artist: "Taylor Swift"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .looseTitleArtist)
        #expect(e.visibility == .looseFallback)
    }

    @Test("Loose matching works when the query is the longer title")
    func looseIsBidirectional() {
        #expect(titleMatchLevel(query: "lacy the redemption", candidate: "lacy") == .loose)
        #expect(titleMatchLevel(query: "lacy", candidate: "lacy the redemption") == .loose)
    }

    @Test("Different songs sharing a word still don't match")
    func differentSongsStayApart() {
        #expect(titleMatchLevel(query: "you and i", candidate: "you and me") == .none)
    }

    @Test("Decorated query + exact artist evaluates as a normal strong candidate")
    func decoratedQueryEvaluation() {
        let lyrics = Lyrics("[ti:Wonderwall]\n[ar:Oasis]\n[00:01.000]line one\n[00:05.000]line two")!
        let e = LyricsCandidateEvaluator().evaluate(
            lyrics: lyrics,
            mode: .titleAndArtist(title: "Wonderwall (2014 Remaster)", artist: "Oasis"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.visibility == .normal)
        #expect(e.matchTier == .strongTitleArtist)
    }
}

@Suite("Token Normalization")
struct TokenNormalizationTests {
    @Test("Apostrophe variants are removed, not turned into word breaks", arguments: ["Don't", "Don’t", "Donʼt", "Dont"])
    func apostrophes(variant: String) {
        #expect(normalizedTokens(variant) == ["dont"])
    }

    @Test("& and 'and' are interchangeable in both directions")
    func ampersand() {
        #expect(normalizedString("Me & You") == normalizedString("Me and You"))
        #expect(titleMatchLevel(query: "Me and You", candidate: "Me & You") == .exact)
        #expect(titleMatchLevel(query: "Me & You", candidate: "Me and You") == .exact)
    }

    @Test("Full-width characters fold to their ASCII forms")
    func widthInsensitive() {
        #expect(normalizedTokens("Ｔｏｋｙｏ") == ["tokyo"])
    }

    @Test("Combining marks don't split words (Devanagari virama)")
    func graphemeClusters() {
        #expect(normalizedTokens("नमस्ते").count == 1)
    }
}

@Suite("Artist Separators")
struct ArtistSeparatorTests {
    @Test("Collaboration separators keep the first artist primary", arguments: [
        "YOASOBI × Ayase", "YOASOBI + Ayase", "YOASOBI; Ayase", "YOASOBI ＆ Ayase",
    ])
    func separators(candidate: String) {
        #expect(artistRelation(query: "YOASOBI", candidate: candidate) == .exactPrimary)
    }

    @Test("Band names spelled with + / & / and are the same artist")
    func wholeNameComparison() {
        #expect(artistRelation(query: "Florence + The Machine", candidate: "Florence and the Machine") == .exactPrimary)
        #expect(artistRelation(query: "Florence and the Machine", candidate: "Florence + The Machine") == .exactPrimary)
    }

    @Test("Names spelled with or without inner punctuation are the same artist", arguments: [
        ("AC/DC", "AC-DC"), ("AC/DC", "ACDC"), ("AC/DC", "AC DC"), ("t.A.T.u.", "Tatu"),
    ])
    func innerPunctuation(query: String, candidate: String) {
        #expect(artistRelation(query: query, candidate: candidate) == .exactPrimary)
        #expect(artistRelation(query: candidate, candidate: query) == .exactPrimary)
    }

    @Test("Punctuation-only artist names still match themselves")
    func punctuationOnly() {
        #expect(artistRelation(query: "!!!", candidate: "!!!") == .exactPrimary)
        #expect(artistRelation(query: "!!!", candidate: "Oasis") == .weak)
    }
}
