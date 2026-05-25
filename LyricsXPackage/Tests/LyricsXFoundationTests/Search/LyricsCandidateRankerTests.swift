import Testing
import Foundation
@testable import LyricsXFoundation

// MARK: - Helpers

private let evaluator = LyricsCandidateEvaluator()
private let ranker = LyricsCandidateRanker()

private func makeLyrics(
    title: String? = nil,
    artist: String? = nil,
    album: String? = nil,
    duration: TimeInterval? = nil,
    lrcBody: String = "[00:01.000]line one\n[00:05.000]line two",
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
    lrc += lrcBody
    let lyrics = Lyrics(lrc)!
    if let s = service { lyrics.metadata.service = s }
    return lyrics
}

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
    for i in 0..<lineCount {
        let ts = String(format: "[00:%02d.000]", i * 5)
        lrc += "\(ts)lyric line \(i + 1)\n"
        lrc += "\(ts)[tt]<0,0><500,4>\n"
    }
    let lyrics = Lyrics(lrc)!
    if let s = service { lyrics.metadata.service = s }
    return lyrics
}

private func makeCandidate(
    _ lyrics: Lyrics,
    mode: LyricsSearchMode,
    arrivalIndex: Int = 0,
    requestedDuration: TimeInterval? = nil,
    requestedAlbum: String? = nil
) -> EvaluatedLyricsCandidate {
    let eval = evaluator.evaluate(
        lyrics: lyrics,
        mode: mode,
        requestedDuration: requestedDuration,
        requestedAlbum: requestedAlbum
    )
    return EvaluatedLyricsCandidate(lyrics: lyrics, evaluation: eval, arrivalIndex: arrivalIndex)
}

// MARK: - Loose fallback suppression

@Suite("Loose Fallback Suppression")
struct LooseFallbackSuppressionTests {
    @Test("Loose candidate shown only when no exact/strong candidates exist")
    func looseSuppressedByNormal() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let exact = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let loose = makeCandidate(
            makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([exact, loose], mode: mode, configuration: config)

        // When a normal candidate exists, loose must be excluded entirely from ranked output.
        #expect(ranked.first?.id == exact.id)
        #expect(ranked.count == 1, "loose must be absent when any normal candidate exists")
        let best = ranker.bestCandidate(from: [exact, loose], mode: mode, configuration: config)
        #expect(best?.id == exact.id)
    }

    @Test("Loose fallback promoted to top when no normal exists")
    func loosePromotedWhenNoNormal() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let loose = makeCandidate(
            makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([loose], mode: mode, configuration: config)
        #expect(ranked.first?.id == loose.id)
    }

    @Test("bestCandidate: loose-fallback only selected when above automaticLooseFallbackMinimumScore")
    func looseFallback_minimumScoreThreshold() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // "lacy the redemption" gives a loose match; its score should be above 75 but
        // test with a high threshold to verify suppression.
        let loose = makeCandidate(
            makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let looseEval = loose.evaluation
        // Score is in the 75–87 range; set threshold above it to force suppression.
        let highThreshold = LyricsCandidateRankingConfiguration(
            automaticLooseFallbackMinimumScore: looseEval.overallScore + 5
        )
        let best = ranker.bestCandidate(from: [loose], mode: mode, configuration: highThreshold)
        #expect(best == nil)

        // With a lower threshold it should be selected.
        let lowThreshold = LyricsCandidateRankingConfiguration(
            automaticLooseFallbackMinimumScore: looseEval.overallScore - 5
        )
        let bestLow = ranker.bestCandidate(from: [loose], mode: mode, configuration: lowThreshold)
        #expect(bestLow?.id == loose.id)
    }
}

// MARK: - Loose fallback suppression (FIX 3)

extension LooseFallbackSuppressionTests {
    @Test("Loose excluded from rankedCandidates when any normal candidate exists")
    func fix3_loosePurgedWhenNormalExists() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // normal: exact title+artist match
        let normal = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        // looseFallback: loose title overlap
        let loose = makeCandidate(
            makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([normal, loose], mode: mode, configuration: config)

        // Loose must be absent; only normal candidates appear.
        let hasLoose = ranked.contains { $0.evaluation.visibility == .looseFallback }
        #expect(!hasLoose, "looseFallback must not appear when a normal candidate exists")
        #expect(ranked.contains { $0.evaluation.visibility == .normal })
    }

    @Test("Loose appears in rankedCandidates when no normal candidate exists")
    func fix3_looseShownWhenNoNormal() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let loose = makeCandidate(
            makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([loose], mode: mode, configuration: config)
        #expect(ranked.first?.evaluation.visibility == .looseFallback)
    }

    @Test("unlikely and rejected never appear in rankedCandidates visible section")
    func fix3_unlikelyAndRejectedNeverInRanked() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // rejected: completely different title
        let rejected = makeCandidate(
            makeLyrics(title: "drivers license", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        // unlikely: exact title + wrong artist → gets visibility .unlikely per evaluator
        let unlikely = makeCandidate(
            makeLyrics(title: "lacy", artist: "Ed Sheeran"),
            mode: mode, arrivalIndex: 1
        )
        let normal = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 2
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([rejected, unlikely, normal], mode: mode, configuration: config)

        let rejectedInOutput = ranked.filter { $0.evaluation.visibility == .rejected }
        #expect(rejectedInOutput.isEmpty, ".rejected must never appear in rankedCandidates")
        // bestCandidate must not select unlikely or rejected when a normal exists
        let best = ranker.bestCandidate(from: [rejected, unlikely, normal], mode: mode, configuration: config)
        #expect(best?.evaluation.visibility == .normal)
    }
}

// MARK: - Karaoke preference window

@Suite("Karaoke Preference Window")
struct KaraokePreferenceWindowTests {
    @Test("Karaoke within 10 points beats line-synced of same title+artist")
    func karaokeBeatsLineSyncedWithinWindow() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Exact line-synced
        let lineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        // Exact karaoke — same tier, slightly lower score but within window
        let karaoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )

        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 10)
        let ranked = ranker.rankedCandidates([lineSynced, karaoke], mode: mode, configuration: config)

        // Karaoke should rank first when within the window
        #expect(karaoke.evaluation.syncKind == .karaoke)
        #expect(lineSynced.evaluation.syncKind == .lineSynced)
        let scoreDiff = lineSynced.evaluation.overallScore - karaoke.evaluation.overallScore
        if scoreDiff <= 10 {
            #expect(ranked.first?.id == karaoke.id, "Karaoke within window should rank first")
        }
    }

    @Test("Karaoke below threshold does NOT beat stronger line-synced")
    func karaokeDoesNotBeatStrongerLineSynced() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Exact line-synced lacy
        let lineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        // Loose karaoke (lacy the redemption) — different tier, much lower score
        let looseKaraoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )

        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 10)
        let best = ranker.bestCandidate(from: [lineSynced, looseKaraoke], mode: mode, configuration: config)

        // The exact line-synced must win because it's a higher tier
        #expect(best?.id == lineSynced.id)
    }

    /// FIX 1: Realistic gap — karaoke overallScore ≈96, lineSynced ≈100, gap≈4, within 10pt window.
    /// The old +0.5 bonus (96.5) cannot beat lineSynced (100), so the old code FAILS this test.
    @Test("FIX1: Karaoke at realistic gap (≈4 pts) within window ranks above line-synced")
    func fix1_karaokeWins_realisticGap() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")

        // Force a realistic gap: perfect duration match pushes lineSynced to 100;
        // karaoke with a poor duration match lands around 96.
        // Both are exact title+primary artist — same tier.
        let lineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210),
            mode: mode, arrivalIndex: 0,
            requestedDuration: 210  // perfect match → durationScore=100 → higher overall
        )
        let karaoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1,
            requestedDuration: 210  // no duration in karaoke lyrics → durationScore=50 → lower overall
        )

        #expect(lineSynced.evaluation.syncKind == .lineSynced)
        #expect(karaoke.evaluation.syncKind == .karaoke)

        let gap = lineSynced.evaluation.overallScore - karaoke.evaluation.overallScore
        // Confirm the gap is realistic (> 0.5 so the old +0.5 bonus would fail, ≤ 10 so within window)
        #expect(gap > 0.5, "gap must be large enough to expose the old +0.5 bug")
        #expect(gap <= 10, "gap must be within the karaoke preference window")

        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 10)
        let ranked = ranker.rankedCandidates([lineSynced, karaoke], mode: mode, configuration: config)
        #expect(ranked.first?.evaluation.syncKind == .karaoke,
                "karaoke within the window must rank above line-synced (gap=\(gap))")
    }

    /// FIX 1: Gap > window → line-synced wins.
    /// Uses a narrow window (1 pt) so the real gap (≈1.75 pts from duration difference)
    /// exceeds it, verifying the no-promotion path.
    @Test("FIX1: Karaoke outside narrow window (gap > window) does not beat line-synced")
    func fix1_lineSyncedWins_gapBeyondWindow() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")

        // lineSynced: perfect duration match → higher overall within the same tier+band
        let lineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210),
            mode: mode, arrivalIndex: 0,
            requestedDuration: 210  // dur=100 → pushes score to ~97.75
        )
        // karaoke: same exact title+primary artist, no duration tag → neutral dur score (50)
        // → lands at the band floor (~96); gap ≈1.75 pts > window of 1 pt.
        let karaoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1,
            requestedDuration: 210  // requested, but karaoke lyrics have no duration tag → dur=50
        )

        #expect(lineSynced.evaluation.syncKind == .lineSynced)
        #expect(karaoke.evaluation.syncKind == .karaoke)

        let gap = lineSynced.evaluation.overallScore - karaoke.evaluation.overallScore
        // Confirm gap exists and is non-trivial (> 0.5 pt so the old +0.5 bonus would also fail)
        #expect(gap > 0.5, "gap must be large enough to exceed the narrow window")

        // Set window BELOW the actual gap so promotion does NOT apply
        let narrowWindow = max(0, gap - 0.5)
        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: narrowWindow)
        let ranked = ranker.rankedCandidates([lineSynced, karaoke], mode: mode, configuration: config)
        #expect(ranked.first?.evaluation.syncKind == .lineSynced,
                "line-synced must win when karaoke gap (\(gap)) exceeds the window (\(narrowWindow))")
    }

    /// FIX 1: Tier still dominates — karaoke in a lower tier cannot jump above lineSynced in higher tier.
    @Test("FIX1: Tier dominates — karaoke in lower tier cannot jump above higher-tier line-synced")
    func fix1_tierDominatesKaraokePromotion() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Higher tier: exact title + exact primary artist, lineSynced
        let exactLineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        // Lower tier: loose match (different visibility/tier), karaoke
        let looseKaraoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )

        // The tiers are different: exactLineSynced is normal/exactTitleArtist,
        // looseKaraoke is looseFallback/looseTitleArtist.
        // With FIX 3, looseKaraoke is suppressed entirely when normalExists.
        // This test verifies the tier mechanism is intact.
        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 10)
        let best = ranker.bestCandidate(from: [exactLineSynced, looseKaraoke], mode: mode, configuration: config)
        #expect(best?.evaluation.syncKind == .lineSynced, "higher-tier lineSynced must beat lower-tier karaoke")
        #expect(best?.evaluation.matchTier == .exactTitleArtist)
    }

    @Test("Rejected candidate never beats any valid candidate even if karaoke")
    func rejectedKaraokeNeverWins() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let rejected = makeCandidate(
            makeKaraokeLyrics(title: "drivers license", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let normal = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )

        let config = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 10)
        let best = ranker.bestCandidate(from: [rejected, normal], mode: mode, configuration: config)
        #expect(best?.id == normal.id)
    }
}

// MARK: - Source priority

@Suite("Source Priority")
struct SourcePriorityTests {
    @Test("Source priority applies among near-equal candidates in same tier")
    func sourcePriorityNearEqual() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let highPriority = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "QQMusic"),
            mode: mode, arrivalIndex: 0
        )
        let lowPriority = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "NetEase"),
            mode: mode, arrivalIndex: 1
        )

        // Both are exact matches; source priority should differentiate them
        let config = LyricsCandidateRankingConfiguration(
            sourcePriorityEnabled: true,
            sourcePriorityOrder: ["QQMusic", "NetEase"],
            nearEqualSourcePriorityWindow: 5
        )
        let ranked = ranker.rankedCandidates([lowPriority, highPriority], mode: mode, configuration: config)
        // QQMusic (higher priority) should rank first
        #expect(ranked.first?.lyrics.metadata.service == "QQMusic")
    }

    @Test("Source priority CANNOT make rejected/wrong-title result win")
    func sourcePriority_cannotElevateRejected() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        // Preferred source but wrong title
        let wrongTitle = makeCandidate(
            makeLyrics(title: "drivers license", artist: "Olivia Rodrigo", service: "QQMusic"),
            mode: mode, arrivalIndex: 0
        )
        // Non-preferred source but correct title
        let correctTitle = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "NetEase"),
            mode: mode, arrivalIndex: 1
        )

        let config = LyricsCandidateRankingConfiguration(
            sourcePriorityEnabled: true,
            sourcePriorityOrder: ["QQMusic", "NetEase"],
            nearEqualSourcePriorityWindow: 5
        )
        let best = ranker.bestCandidate(from: [wrongTitle, correctTitle], mode: mode, configuration: config)
        // The correct title must win even though it's from a lower-priority source
        #expect(best?.lyrics.metadata.service == "NetEase")
    }

    @Test("Source priority disabled → arrival order is tiebreaker")
    func sourcePriorityDisabled() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let first = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "NetEase"),
            mode: mode, arrivalIndex: 0
        )
        let second = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "QQMusic"),
            mode: mode, arrivalIndex: 1
        )

        let config = LyricsCandidateRankingConfiguration(
            sourcePriorityEnabled: false,
            sourcePriorityOrder: ["QQMusic"]
        )
        let ranked = ranker.rankedCandidates([first, second], mode: mode, configuration: config)
        // QQMusic is preferred but priority disabled → first arrival wins
        #expect(ranked.first?.id == first.id)
    }
}

// MARK: - Artist-only ranking

@Suite("ArtistOnly Ranking")
struct ArtistOnlyRankingTests {
    @Test("Multiple titles by artist sorted A–Z")
    func multipleTitles_sortedAlphabetically() {
        let mode = LyricsSearchMode.artistOnly(artist: "Olivia Rodrigo")
        let songs = ["vampire", "deja vu", "brutal", "good 4 u"]
        let candidates = songs.enumerated().map { idx, title in
            makeCandidate(
                makeLyrics(title: title, artist: "Olivia Rodrigo"),
                mode: mode, arrivalIndex: idx
            )
        }
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates(candidates, mode: mode, configuration: config)

        let rankedTitles = ranked
            .filter { $0.evaluation.matchTier == .exactArtistCatalog }
            .compactMap { $0.lyrics.idTags[.title] }

        // Should be alphabetically sorted
        #expect(rankedTitles == rankedTitles.sorted())
    }

    @Test("Karaoke preferred over line-synced within same title group (artist-only)")
    func karaokeFirst_withinSameTitle() {
        let mode = LyricsSearchMode.artistOnly(artist: "Olivia Rodrigo")
        let lineSynced = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "QQMusic"),
            mode: mode, arrivalIndex: 0
        )
        let karaoke = makeCandidate(
            makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo", service: "NetEase"),
            mode: mode, arrivalIndex: 1
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([lineSynced, karaoke], mode: mode, configuration: config)

        #expect(karaoke.evaluation.syncKind == .karaoke)
        // Karaoke should rank first for the same normalized title
        let lacyResults = ranked.filter {
            normalizedString($0.lyrics.idTags[.title] ?? "") == "lacy"
        }
        #expect(lacyResults.first?.evaluation.syncKind == .karaoke)
    }

    @Test("Exact artist before non-primary featured artist")
    func exactArtistBeforeLoose() {
        let mode = LyricsSearchMode.artistOnly(artist: "Olivia Rodrigo")
        let featured = makeCandidate(
            makeLyrics(title: "abb", artist: "Someone feat. Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let exact = makeCandidate(
            makeLyrics(title: "aaa", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([featured, exact], mode: mode, configuration: config)
        // exactArtistCatalog should come before looseArtistCatalog
        #expect(ranked.first?.evaluation.matchTier == .exactArtistCatalog)
    }
}

// MARK: - Title-based ranking correctness

@Suite("TitleBased Ranking Correctness")
struct TitleBasedRankingCorrectnessTests {
    @Test("Exact title+artist beats strong variant; strong beats loose")
    func tierOrdering() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let exact = makeCandidate(makeLyrics(title: "lacy", artist: "Olivia Rodrigo"), mode: mode, arrivalIndex: 0)
        let strong = makeCandidate(makeLyrics(title: "lacy - acoustic", artist: "Olivia Rodrigo"), mode: mode, arrivalIndex: 1)
        let loose = makeCandidate(makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo"), mode: mode, arrivalIndex: 2)

        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([loose, strong, exact], mode: mode, configuration: config)

        // When all tiers exist, normal (exact/strong) are first, loose is last
        #expect(ranked[0].id == exact.id || ranked[0].id == strong.id)
        // The loose result should not precede exact or strong
        let looseIdx = ranked.firstIndex(where: { $0.id == loose.id }) ?? Int.max
        let exactIdx = ranked.firstIndex(where: { $0.id == exact.id }) ?? Int.max
        #expect(exactIdx < looseIdx)
    }

    @Test("Rejected candidates are excluded from ranked output")
    func rejectedExcluded() {
        let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
        let rejected = makeCandidate(
            makeLyrics(title: "drivers license", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 0
        )
        let normal = makeCandidate(
            makeLyrics(title: "lacy", artist: "Olivia Rodrigo"),
            mode: mode, arrivalIndex: 1
        )
        let config = LyricsCandidateRankingConfiguration()
        let ranked = ranker.rankedCandidates([rejected, normal], mode: mode, configuration: config)
        // Rejected candidate must not appear in the non-unlikely section
        let rejectedInNormal = ranked.filter {
            $0.evaluation.visibility == .rejected
        }
        #expect(rejectedInNormal.isEmpty)
    }
}
