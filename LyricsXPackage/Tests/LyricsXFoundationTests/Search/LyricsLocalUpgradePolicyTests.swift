import Testing
import Foundation
@testable import LyricsXFoundation

// MARK: - Helpers

private let evaluator = LyricsCandidateEvaluator()
private let defaultConfig = LyricsCandidateRankingConfiguration()

private func makeLyrics(
    title: String? = nil,
    artist: String? = nil,
    duration: TimeInterval? = nil,
    lrcBody: String = "[00:01.000]line one\n[00:05.000]line two",
    service: String? = nil
) -> Lyrics {
    var lrc = ""
    if let t = title  { lrc += "[ti:\(t)]\n" }
    if let a = artist { lrc += "[ar:\(a)]\n" }
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
    duration: TimeInterval? = nil,
    lineCount: Int = 4,
    service: String? = nil
) -> Lyrics {
    var lrc = ""
    if let t = title  { lrc += "[ti:\(t)]\n" }
    if let a = artist { lrc += "[ar:\(a)]\n" }
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

private func evaluate(
    _ lyrics: Lyrics,
    mode: LyricsSearchMode = .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
    duration: TimeInterval? = nil,
    album: String? = nil
) -> LyricsCandidateEvaluation {
    evaluator.evaluate(lyrics: lyrics, mode: mode, requestedDuration: duration, requestedAlbum: album)
}

// MARK: - Case 16: Local karaoke not replaced

@Suite("Local Upgrade Policy — Case 16: Local karaoke not replaced")
struct LocalKaraokeNotReplacedTests {
    // The upstream guard in LyricsSession.currentTrackChanged returns early when
    // local lyrics are karaoke-timed, so shouldRemoteUpgradeLocal is never reached
    // for a karaoke-local case. This test verifies that the policy function itself
    // correctly handles weak/loose/unlikely remote candidates — confirming the function
    // is not the wrong place to put the karaoke-local short-circuit.

    @Test("Loose/weak remote cannot replace local line-synced (policy rejects non-exact/strong tier)")
    func loose_remote_cannot_replace_local() {
        // local: a well-matched line-synced candidate
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210)
        let localEval = evaluate(local, duration: 210)
        #expect(localEval.visibility == .normal)

        // remote: a loose-title match (looseFallback) — should be rejected by policy
        let looseRemote = makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo")
        let looseEval = evaluate(looseRemote)
        #expect(looseEval.visibility == .looseFallback)

        let result = shouldRemoteUpgradeLocal(
            candidate: looseEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "loose fallback remote must not replace local line-synced")
    }

    @Test("Unlikely remote cannot replace local line-synced (policy rejects non-normal visibility)")
    func unlikely_remote_cannot_replace_local() {
        // local: a well-matched line-synced candidate
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local)

        // remote: exact title but wrong artist → unlikely
        let unlikely = makeLyrics(title: "lacy", artist: "Ed Sheeran")
        let unlikelyEval = evaluate(unlikely)
        #expect(unlikelyEval.visibility == .unlikely)

        let result = shouldRemoteUpgradeLocal(
            candidate: unlikelyEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "unlikely remote must not replace local line-synced")
    }
}

// MARK: - Case 17: Local line-synced replaced by strong karaoke within threshold

@Suite("Local Upgrade Policy — Case 17: Local line-synced replaced by strong karaoke")
struct LocalLineSyncedKaraokeUpgradeTests {
    @Test("Strong karaoke within 10-point window replaces local line-synced (gap=4)")
    func karaokeWithinWindow_replaces() {
        // local: exact match with perfect duration → score ~97-100
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210)
        let localEval = evaluate(local, duration: 210)
        #expect(localEval.visibility == .normal)
        #expect(localEval.syncKind == .lineSynced)

        // remote karaoke: exact match, no duration tag → neutral duration → score ~96
        let karaokeRemote = makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let karaokeEval = evaluate(karaokeRemote, duration: 210)
        #expect(karaokeEval.syncKind == .karaoke)
        #expect(karaokeEval.visibility == .normal)
        #expect(karaokeEval.matchTier == .exactTitleArtist)

        let gap = localEval.overallScore - karaokeEval.overallScore
        // Gap should be within the 10-point window for this to be a valid test
        #expect(gap <= 10, "gap (\(gap)) must be within the karaoke window for this test to be meaningful")

        let result = shouldRemoteUpgradeLocal(
            candidate: karaokeEval,
            local: localEval,
            configuration: defaultConfig  // karaokePreferenceWindow = 10
        )
        #expect(result, "karaoke within 10-point window must replace local line-synced (gap=\(gap))")
    }

    @Test("Strong karaoke scoring higher than local always replaces (gap negative)")
    func karaokeHigherThanLocal_alwaysReplaces() {
        // local: exact match, no duration → neutral duration score → lower overall
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local, duration: 210)  // no duration in lyrics → neutral

        // remote karaoke: exact match, perfect duration → higher overall
        let karaokeRemote = makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210)
        let karaokeEval = evaluate(karaokeRemote, duration: 210)
        #expect(karaokeEval.syncKind == .karaoke)
        #expect(karaokeEval.matchTier == .exactTitleArtist)

        // gap = localScore - candidateScore; negative means candidate scored higher
        let gap = localEval.overallScore - karaokeEval.overallScore
        #expect(gap < 0, "karaoke should score higher than local in this scenario (gap=\(gap))")

        let result = shouldRemoteUpgradeLocal(
            candidate: karaokeEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(result, "karaoke scoring higher than local must always replace (no lower bound)")
    }

    @Test("Karaoke far below threshold (gap=18) does NOT replace local line-synced")
    func karaokeFarBelowThreshold_doesNotReplace() {
        // local: exact match with perfect duration → high score
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo", duration: 210)
        let localEval = evaluate(local, duration: 210)

        // Force a scenario with gap > 10: use a narrow config window
        let narrowConfig = LyricsCandidateRankingConfiguration(karaokePreferenceWindow: 0)

        let karaokeRemote = makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let karaokeEval = evaluate(karaokeRemote, duration: 210)
        #expect(karaokeEval.syncKind == .karaoke)

        let gap = localEval.overallScore - karaokeEval.overallScore
        // With window=0, only a negative gap (karaoke scores higher) would pass
        #expect(gap > 0, "karaoke should score lower than local in this scenario")

        let result = shouldRemoteUpgradeLocal(
            candidate: karaokeEval,
            local: localEval,
            configuration: narrowConfig  // window=0, so gap must be ≤0 to upgrade
        )
        #expect(!result, "karaoke outside window must not replace local line-synced (gap=\(gap), window=0)")
    }
}

// MARK: - Case 18: Local line-synced replaced by materially better line-synced

/// Builds a minimal `LyricsCandidateEvaluation` for use in upgrade-policy tests.
///
/// `shouldRemoteUpgradeLocal` reads only `visibility`, `matchTier`, `syncKind`,
/// and `overallScore`, so the remaining fields are filled with neutral sentinels.
private func makeSyntheticEval(
    visibility: LyricsCandidateVisibility = .normal,
    matchTier: LyricsCandidateMatchTier = .exactTitleArtist,
    syncKind: LyricsSyncKind = .lineSynced,
    overallScore: Double
) -> LyricsCandidateEvaluation {
    LyricsCandidateEvaluation(
        mode: .titleAndArtist(title: "lacy", artist: "Olivia Rodrigo"),
        visibility: visibility,
        matchTier: matchTier,
        syncKind: syncKind,
        titleScore: 100,
        artistScore: 100,
        durationScore: 50,
        albumScore: 50,
        overallScore: overallScore,
        rejectionReason: nil
    )
}

@Suite("Local Upgrade Policy — Case 18: Local line-synced replaced by materially better line-synced")
struct LocalLineSyncedMateriallyBetterTests {
    @Test("Remote line-synced with score = local+5 replaces local (exact threshold)")
    func lineSynced_materiallyBetter_replaces() {
        let localEval = makeSyntheticEval(overallScore: 90)
        let candidateAtThreshold = makeSyntheticEval(overallScore: 95)  // exactly +5

        let result = shouldRemoteUpgradeLocal(
            candidate: candidateAtThreshold,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(result, "remote line-synced at exactly local+5 must replace local")
    }

    @Test("Remote line-synced with score = local+4 does NOT replace local (just below threshold)")
    func lineSynced_justBelowThreshold_doesNotReplace() {
        let localEval = makeSyntheticEval(overallScore: 90)
        let candidateBelow = makeSyntheticEval(overallScore: 94)  // +4, one short of threshold

        let result = shouldRemoteUpgradeLocal(
            candidate: candidateBelow,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "remote line-synced at local+4 must NOT replace local (threshold is +5)")
    }

    @Test("Remote line-synced with same score does NOT replace local (+0, below +5 threshold)")
    func lineSynced_sameScore_doesNotReplace() {
        let localEval = makeSyntheticEval(overallScore: 90)
        let remoteEval = makeSyntheticEval(overallScore: 90)

        let result = shouldRemoteUpgradeLocal(
            candidate: remoteEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "remote line-synced at equal score must not replace local (needs +5)")
    }
}

// MARK: - Case 19: Loose/weak/rejected/unlikely remote cannot replace local

@Suite("Local Upgrade Policy — Case 19: Weak/rejected/unlikely remote cannot replace local")
struct LocalUpgradeGuardTests {
    @Test("Rejected remote (visibility .rejected) cannot replace local")
    func rejected_cannotReplace() {
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local)

        let rejected = makeLyrics(title: "drivers license", artist: "Olivia Rodrigo")
        let rejectedEval = evaluate(rejected)
        #expect(rejectedEval.visibility == .rejected)

        let result = shouldRemoteUpgradeLocal(
            candidate: rejectedEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "rejected remote must not replace local")
    }

    @Test("Loose/looseTitleArtist tier remote cannot replace local (non-exact/strong tier)")
    func looseTier_cannotReplace() {
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local)

        // lacy the redemption → looseFallback / looseTitleArtist tier
        let loose = makeLyrics(title: "lacy the redemption", artist: "Olivia Rodrigo")
        let looseEval = evaluate(loose)
        #expect(looseEval.visibility == .looseFallback)
        #expect(looseEval.matchTier == .looseTitleArtist)

        let result = shouldRemoteUpgradeLocal(
            candidate: looseEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "looseTitleArtist tier remote must not replace local (tier guard)")
    }

    @Test("Unlikely remote cannot replace local (wrong artist)")
    func unlikely_cannotReplace() {
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local)

        // Exact title + wrong artist → unlikely
        let unlikely = makeLyrics(title: "lacy", artist: "Wrong Artist")
        let unlikelyEval = evaluate(unlikely)
        #expect(unlikelyEval.visibility == .unlikely)

        let result = shouldRemoteUpgradeLocal(
            candidate: unlikelyEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(!result, "unlikely remote must not replace local")
    }

    @Test("Strong karaoke remote passes tier guard (exactTitleArtist, normal)")
    func strongKaraoke_passesGuard() {
        // local: reasonable score without duration match
        let local = makeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let localEval = evaluate(local)

        // remote: exact match karaoke within window → should pass
        let remote = makeKaraokeLyrics(title: "lacy", artist: "Olivia Rodrigo")
        let remoteEval = evaluate(remote)
        #expect(remoteEval.visibility == .normal)
        #expect(remoteEval.matchTier == .exactTitleArtist)
        #expect(remoteEval.syncKind == .karaoke)

        // Both have same score (no duration data) → gap = 0 ≤ 10 → should upgrade
        let gap = localEval.overallScore - remoteEval.overallScore
        let result = shouldRemoteUpgradeLocal(
            candidate: remoteEval,
            local: localEval,
            configuration: defaultConfig
        )
        #expect(result, "exact/strong karaoke must pass upgrade guard when within window (gap=\(gap))")
    }
}
