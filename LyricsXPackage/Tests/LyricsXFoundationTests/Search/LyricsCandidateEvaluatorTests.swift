import Testing
import Foundation
@testable import LyricsXFoundation

// MARK: - Helpers

/// Builds a minimal Lyrics object from LRC text.
private func makeLyrics(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    duration: TimeInterval? = nil,
    lrcBody: String = "[00:01.000]line one\n[00:05.000]line two",
    karaokeBody: String? = nil,
    service: String? = nil
) -> Lyrics {
    var lrc = ""
    if let t = title  { lrc += "[ti:\(t)]\n" }
    if let a = artist { lrc += "[ar:\(a)]\n" }
    if let a = album  { lrc += "[al:\(a)]\n" }
    if let d = duration {
        let min = Int(d / 60)
        let sec = d - Double(min * 60)
        lrc += String(format: "[length:%02d:%06.3f]\n", min, sec)
    }
    lrc += (karaokeBody ?? lrcBody)
    let lyrics = Lyrics(lrc)!
    if let s = service { lyrics.metadata.service = s }
    return lyrics
}

/// Builds a karaoke lyrics object by embedding [tt] attachments on each line.
/// The LRC parser attaches `[tt]` inline timetags when they appear in the
/// attachment line format: `[<timestamp>][tt]<timetag_content>`.
private func makeKaraokeLyrics(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    duration: TimeInterval? = nil,
    lineCount: Int = 4,
    service: String? = nil
) -> Lyrics {
    var lrc = ""
    if let t = title  { lrc += "[ti:\(t)]\n" }
    if let a = artist { lrc += "[ar:\(a)]\n" }
    if let a = album  { lrc += "[al:\(a)]\n" }
    if let d = duration {
        let min = Int(d / 60)
        let sec = d - Double(min * 60)
        lrc += String(format: "[length:%02d:%06.3f]\n", min, sec)
    }
    // Each line gets a timetag attachment so coverage is 100%
    for i in 0..<lineCount {
        let sec = i * 5
        let ts = String(format: "[00:%02d.000]", sec)
        lrc += "\(ts)lyric line \(i + 1)\n"
        lrc += "\(ts)[tt]<0,0><500,4>\n"
    }
    let lyrics = Lyrics(lrc)!
    if let s = service { lyrics.metadata.service = s }
    return lyrics
}

// MARK: - Sync detection tests

@Suite("Sync Detection")
struct SyncDetectionTests {
    @Test("Line-synced lyrics without any timetag attachment")
    func lineSyncedNoTimetag() {
        let l = makeLyrics(lrcBody: "[00:01.000]line one\n[00:05.000]line two")
        #expect(l.syncKind == .lineSynced)
        #expect(!l.isKaraokeTimed)
    }

    @Test("One stray timetag line does NOT mark the whole result as karaoke")
    func oneTimetag_notKaraoke() {
        // 1 line has [tt], 3 do not → below the 50% and count-2 thresholds
        var lrc = "[00:01.000]line one\n"
        lrc += "[00:01.000][tt]<0,0><500,4>\n"
        lrc += "[00:05.000]line two\n"
        lrc += "[00:09.000]line three\n"
        lrc += "[00:13.000]line four\n"
        let l = Lyrics(lrc)!
        #expect(l.syncKind == .lineSynced)
    }

    @Test("Karaoke requires ≥2 tagged lines AND ≥50% coverage")
    func karaoke_twoTaggedLines_qualifies() {
        let l = makeKaraokeLyrics(lineCount: 4)
        #expect(l.syncKind == .karaoke)
        #expect(l.isKaraokeTimed)
    }

    @Test("Two tagged out of two lines → karaoke (100% coverage, count ≥2)")
    func karaoke_twoOfTwo() {
        var lrc = "[00:01.000]line one\n"
        lrc += "[00:01.000][tt]<0,0><500,4>\n"
        lrc += "[00:05.000]line two\n"
        lrc += "[00:05.000][tt]<0,0><500,4>\n"
        let l = Lyrics(lrc)!
        #expect(l.syncKind == .karaoke)
    }

    @Test("Two tagged out of five lines → 40% coverage, below threshold → lineSynced")
    func karaoke_twoOfFive_notEnough() {
        var lrc = ""
        for i in 0..<5 {
            let ts = String(format: "[00:%02d.000]", i * 5)
            lrc += "\(ts)line \(i)\n"
            if i < 2 {
                lrc += "\(ts)[tt]<0,0><500,4>\n"
            }
        }
        let l = Lyrics(lrc)!
        #expect(l.syncKind == .lineSynced)
    }
}

// MARK: - titleAndArtist mode evaluator tests

@Suite("TitleAndArtist Evaluation")
struct TitleAndArtistEvaluatorTests {
    let evaluator = LyricsCandidateEvaluator()

    @Test("Exact title+artist → exactTitleArtist, normal, score 95–100")
    func exactTitleArtist() {
        let l = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .exactTitleArtist)
        #expect(e.visibility == .normal)
        #expect(e.overallScore >= 92 && e.overallScore <= 100)
        #expect(e.rejectionReason == nil)
    }

    @Test("Wrong title same artist → rejected")
    func wrongTitleSameArtist_rejected() {
        let l = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .rejected)
        #expect(e.visibility == .rejected)
        #expect(e.rejectionReason == .titleMismatch)
    }

    @Test("Exact title beats wrong-title-same-artist")
    func exactBeatsWrongTitle() {
        let exact = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let wrong = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo")
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let eExact = evaluator.evaluate(lyrics: exact, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        let eWrong = evaluator.evaluate(lyrics: wrong, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        #expect(eExact.matchTier.titleBasedPriority > eWrong.matchTier.titleBasedPriority)
        #expect(eExact.visibility == .normal)
        #expect(eWrong.visibility == .rejected)
    }

    @Test("lacy the redemption → loose title overlap (not exact, not rejected)")
    func lacyRedemption_isLoose() {
        let l = makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .looseTitleArtist)
        #expect(e.visibility == .looseFallback)
    }

    @Test("lacy vs drivers license → rejected (no whole-token overlap)")
    func driversLicense_rejected() {
        let l = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.visibility == .rejected)
    }

    @Test("lacy - acoustic → strong variant (core token match)")
    func lacyAcoustic_isStrong() {
        let l = makeLyrics(title: "lacy - acoustic", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .strongTitleArtist)
        #expect(e.visibility == .normal)
    }

    @Test("Exact title + missing artist → strongTitleArtist, normal (capped below confirmed exact)")
    func exactTitleMissingArtist() {
        let l = makeLyrics(title: "lacy", artist: nil)
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .strongTitleArtist)
        #expect(e.visibility == .normal)
    }

    @Test("Artist feat. X where feat. artist matches query → exactNonPrimary relation")
    func featuredArtist_exactNonPrimary() {
        let l = makeLyrics(title: "lacy", artist: "Someone feat. Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        // exactNonPrimary is still a strong relation → should be normal
        #expect(e.visibility == .normal)
        #expect(e.matchTier == .exactTitleArtist || e.matchTier == .strongTitleArtist)
    }

    /// FIX 2: exactPrimary band (96–100) must be strictly above exactNonPrimary band (92–95),
    /// so a primary artist always ranks above a non-primary/featured artist match for the same
    /// title, even when the non-primary has perfect duration+album tiebreakers.
    @Test("FIX2: Exact primary artist always ranks above exact non-primary even with better tiebreakers")
    func fix2_primaryAlwaysBeatsNonPrimary() {
        let evaluator = LyricsCandidateEvaluator()
        let ranker = LyricsCandidateRanker()
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")

        // Candidate A: exact primary match ("Olivia Rodrigo"), poor duration+album
        let primary = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        // No duration or album provided → neutral tiebreaker scores (50)
        let eA = evaluator.evaluate(lyrics: primary, mode: mode, requestedDuration: 210, requestedAlbum: "GUTS")

        // Candidate B: exact non-primary/featured match ("lacy / X feat. Olivia Rodrigo"),
        // PERFECT duration and album match → maximum tiebreaker advantage
        let nonPrimary = makeLyrics(
            title: "lacy",
            artist: "Someone feat. Olivia Rodrigo",
            album: "GUTS",
            duration: 210
        )
        let eB = evaluator.evaluate(lyrics: nonPrimary, mode: mode, requestedDuration: 210, requestedAlbum: "GUTS")

        // Both must be in the same exactTitleArtist tier
        #expect(eA.matchTier == .exactTitleArtist)
        #expect(eB.matchTier == .exactTitleArtist)

        // Primary floor (96) must exceed non-primary ceiling (95): no overlap
        #expect(eA.overallScore >= 96, "exactPrimary must score ≥ 96 (band 96–100)")
        #expect(eB.overallScore <= 95, "exactNonPrimary must score ≤ 95 (band 92–95)")
        #expect(eA.overallScore > eB.overallScore,
                "primary (\(eA.overallScore)) must beat non-primary (\(eB.overallScore)) regardless of tiebreakers")

        // Ranker must place primary first
        let candA = EvaluatedLyricsCandidate(lyrics: primary, evaluation: eA, arrivalIndex: 0)
        let candB = EvaluatedLyricsCandidate(lyrics: nonPrimary, evaluation: eB, arrivalIndex: 1)
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([candB, candA], mode: mode, configuration: config)
        #expect(ranked.first?.lyrics.idTags[.artist] == "Olivia Rodrigo",
                "primary artist result must rank first")
    }

    @Test("Duration tiebreaker: near match outranks far match within same tier")
    func durationTiebreaker() {
        let near = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210)
        let far  = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 260)
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let eNear = evaluator.evaluate(lyrics: near, mode: mode, requestedDuration: 211, requestedAlbum: nil)
        let eFar  = evaluator.evaluate(lyrics: far,  mode: mode, requestedDuration: 211, requestedAlbum: nil)
        // Both should be same tier, but near should have higher overall score
        #expect(eNear.matchTier == eFar.matchTier)
        #expect(eNear.overallScore > eFar.overallScore)
    }

    @Test("Album match is positive tiebreaker; album mismatch doesn't reject a correct title")
    func albumTiebreaker() {
        let correct = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", album: "GUTS")
        let wrong   = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo", album: "GUTS")
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let eCorrect = evaluator.evaluate(lyrics: correct, mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")
        let eWrong   = evaluator.evaluate(lyrics: wrong,   mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")
        #expect(eCorrect.visibility == .normal)
        // Album match makes wrong-title result no better — it's still rejected by title
        #expect(eWrong.visibility == .rejected)
    }

    @Test("Non-finite quality is handled safely (no crash)")
    func nonFiniteQualitySafe() {
        let l = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        // Force a non-finite quality into the metadata
        l.metadata.data[Lyrics.Metadata.Key("quality")] = Double.nan
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        // The evaluator must not crash; result must be a valid evaluation
        #expect(e.overallScore.isFinite)
    }

    // MARK: - Case 14: Album match helps only as a tiebreaker

    /// Case 14: Album score is a positive tiebreaker — the evaluator records a
    /// higher albumScore when the album matches, which the ranker uses as a
    /// sort step after duration. This test verifies that albumScore is correctly
    /// set (not overall score, which can be clamped to the band floor).
    @Test("Case 14: Album match gives a higher albumScore than album mismatch within same tier")
    func albumMatch_higherAlbumScore() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Same title+artist → same tier; only album differs
        let withAlbum  = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", album: "GUTS")
        let wrongAlbum = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", album: "Sour")
        let eWithAlbum  = evaluator.evaluate(lyrics: withAlbum,  mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")
        let eWrongAlbum = evaluator.evaluate(lyrics: wrongAlbum, mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")

        // Both must be in the same tier and visibility
        #expect(eWithAlbum.matchTier == eWrongAlbum.matchTier, "same tier required")
        #expect(eWithAlbum.visibility == .normal)
        #expect(eWrongAlbum.visibility == .normal)

        // albumScore must reflect the match (album score is what the ranker uses as tiebreaker)
        #expect(eWithAlbum.albumScore > eWrongAlbum.albumScore,
                "album match (albumScore=\(eWithAlbum.albumScore)) must exceed album mismatch (albumScore=\(eWrongAlbum.albumScore))")
    }

    /// Case 14 (continued): Album is a tiebreaker only — it does not affect match tier.
    @Test("Case 14: Album match does not change the match tier")
    func albumMatch_doesNotChangeTier() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let withAlbum    = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", album: "GUTS")
        let withoutAlbum = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let eWith    = evaluator.evaluate(lyrics: withAlbum,    mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")
        let eWithout = evaluator.evaluate(lyrics: withoutAlbum, mode: mode, requestedDuration: nil, requestedAlbum: "GUTS")

        // Album availability must not change tier/visibility
        #expect(eWith.matchTier == eWithout.matchTier)
        #expect(eWith.visibility == eWithout.visibility)
    }

    // MARK: - Case 15: Album mismatch cannot make a wrong song valid

    /// Case 15: A perfect album match does not rescue a wrong-title candidate from rejection.
    @Test("Case 15: Perfect album match cannot make a wrong-title candidate valid")
    func albumMatch_cannotRescueWrongTitle() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Wrong title, matching album — album should not change the rejection outcome
        let wrongTitleRightAlbum = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo", album: "GUTS")
        let e = evaluator.evaluate(
            lyrics: wrongTitleRightAlbum,
            mode: mode,
            requestedDuration: nil,
            requestedAlbum: "GUTS"
        )
        // Must still be rejected despite perfect album match
        #expect(e.visibility == .rejected, "wrong title must be rejected even with matching album")
        #expect(e.rejectionReason == .titleMismatch)
    }

    /// Case 15 (continued): Album match cannot make a wrong-artist candidate valid.
    @Test("Case 15: Perfect album match cannot make a wrong-artist candidate normal")
    func albumMatch_cannotRescueWrongArtist() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Correct title but completely wrong artist — album matches.
        // Per evaluator: exact title + wrong artist → unlikely (not normal).
        let rightTitleWrongArtist = makeLyrics(title: "lacy", artist: "Ed Sheeran", album: "GUTS")
        let e = evaluator.evaluate(
            lyrics: rightTitleWrongArtist,
            mode: mode,
            requestedDuration: nil,
            requestedAlbum: "GUTS"
        )
        // Must remain unlikely — album match cannot promote to normal
        #expect(e.visibility != .normal, "wrong-artist candidate must not become normal even with matching album")
    }
}

// MARK: - Version marker / core-title stripping tests (FIX 4)

@Suite("CoreTitle Stripping")
struct CoreTitleStrippingTests {
    let evaluator = LyricsCandidateEvaluator()

    /// FIX 4: "and" must no longer be in versionMarkers.
    /// "you and i" vs "you and me" share only "you"; without "and" being stripped,
    /// they produce different core tokens and must NOT be a strong/exact match.
    @Test("FIX4: 'you and i' vs 'you and me' are NOT exact or strong — different songs")
    func fix4_youAndI_vs_youAndMe_notExactOrStrong() {
        let mode = LyricsSearchMode.titleAndArtist(title: "you and i", artist: "Olivia Rodrigo")
        let candidate = makeLyrics(title: "you and me", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(lyrics: candidate, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        // Must NOT be exact or strong — should be loose or rejected
        #expect(e.matchTier != .exactTitleArtist,
                "'you and me' must not be an exact match for 'you and i'")
        #expect(e.matchTier != .strongTitleArtist,
                "'you and me' must not be a strong match for 'you and i' (different songs)")
    }

    /// FIX 4: Genuine variant markers (acoustic) must still strip correctly.
    /// "lacy" vs "lacy - acoustic" → strong (core tokens identical after stripping "acoustic").
    @Test("FIX4: 'lacy' vs 'lacy - acoustic' is still STRONG (acoustic stripping preserved)")
    func fix4_lacyAcoustic_stillStrong() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let candidate = makeLyrics(title: "lacy - acoustic", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(lyrics: candidate, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        #expect(e.matchTier == .strongTitleArtist,
                "'lacy - acoustic' must be a strong variant of 'lacy'")
        #expect(e.visibility == .normal)
    }

    /// FIX 4: "feat" must no longer be in versionMarkers.
    /// A title like "song feat collaborator" would incorrectly strip to "song" otherwise.
    @Test("FIX4: title containing 'feat' is not stripped — no false core equivalence")
    func fix4_featInTitle_notStripped() {
        let mode = LyricsSearchMode.titleAndArtist(title: "you feat me", artist: "Olivia Rodrigo")
        let exact = makeLyrics(title: "you feat me", artist: "Olivia Rodrigo")
        let other = makeLyrics(title: "you feat them", artist: "Olivia Rodrigo")
        let eExact = evaluator.evaluate(lyrics: exact, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        let eOther = evaluator.evaluate(lyrics: other, mode: mode, requestedDuration: nil, requestedAlbum: nil)
        #expect(eExact.matchTier == .exactTitleArtist, "'you feat me' must exactly match itself")
        // "you feat them" must not be strong (they produce different core tokens without stripping)
        #expect(eOther.matchTier != .strongTitleArtist,
                "'you feat them' must not be strong variant of 'you feat me'")
    }
}

// MARK: - titleOnly mode tests

@Suite("TitleOnly Evaluation")
struct TitleOnlyEvaluatorTests {
    let evaluator = LyricsCandidateEvaluator()

    @Test("Exact title match is normal even with artist mismatch")
    func exactTitle_artistMismatch_normal() {
        let l = makeLyrics(title: "lacy", artist: "Someone Else")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleOnly(title: "lacy"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .titleOnly)
        #expect(e.visibility == .normal)
    }

    @Test("No title overlap → rejected in titleOnly mode")
    func noTitleOverlap_rejected() {
        let l = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleOnly(title: "lacy"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.visibility == .rejected)
    }

    @Test("Loose title match → looseFallback in titleOnly mode")
    func looseTitleMatch_looseFallback() {
        let l = makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .titleOnly(title: "lacy"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.visibility == .looseFallback)
    }
}

// MARK: - artistOnly mode tests

@Suite("ArtistOnly Evaluation")
struct ArtistOnlyEvaluatorTests {
    let evaluator = LyricsCandidateEvaluator()

    @Test("Exact primary artist → exactArtistCatalog, normal")
    func exactPrimaryArtist() {
        let l = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .artistOnly(artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .exactArtistCatalog)
        #expect(e.visibility == .normal)
    }

    @Test("Artist feat. queried artist → looseArtistCatalog")
    func featuredArtist_looseArtistCatalog() {
        let l = makeLyrics(title: "song", artist: "Someone feat. Olivia Rodrigo")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .artistOnly(artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.matchTier == .looseArtistCatalog)
        #expect(e.visibility == .normal)
    }

    @Test("Unrelated artist → unlikely")
    func unrelatedArtist_unlikely() {
        let l = makeLyrics(title: "song", artist: "Oliver Rodigan")
        let e = evaluator.evaluate(
            lyrics: l,
            mode: .artistOnly(artist: "Olivia Rodrigo"),
            requestedDuration: nil, requestedAlbum: nil
        )
        #expect(e.visibility == .unlikely)
        #expect(e.matchTier == .rejected)
    }

    @Test("Multiple titles by the same artist all accepted as exactArtistCatalog")
    func multipleTitles_allAccepted() {
        let songs = ["lacy", "drivers license", "deja vu", "good 4 u"]
        let mode = LyricsSearchMode.artistOnly(artist: "Olivia Rodrigo")
        for title in songs {
            let l = makeLyrics(title: title, artist: "Olivia Rodrigo")
            let e = evaluator.evaluate(lyrics: l, mode: mode, requestedDuration: nil, requestedAlbum: nil)
            #expect(e.matchTier == .exactArtistCatalog, "Expected exactArtistCatalog for '\(title)'")
        }
    }
}
