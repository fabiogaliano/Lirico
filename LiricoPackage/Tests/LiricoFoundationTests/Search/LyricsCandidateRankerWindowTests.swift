import Testing
import Foundation
@testable import LiricoFoundation

private let ranker = LyricsCandidateRanker()
private let titleMode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")

private func candidate(
    score: Double,
    service: String,
    tier: LyricsCandidateMatchTier = .exactTitleArtist,
    syncKind: LyricsSyncKind = .lineSynced,
    mode: LyricsSearchMode = titleMode,
    title: String = "lacy",
    arrivalIndex: Int
) -> EvaluatedLyricsCandidate {
    let lyrics = Lyrics("[ti:\(title)]\n[ar:Olivia Rodrigo]\n[00:01.000]line one\n[00:05.000]line two")!
    lyrics.metadata.service = service
    let evaluation = LyricsCandidateEvaluation(
        mode: mode,
        visibility: .normal,
        matchTier: tier,
        syncKind: syncKind,
        titleScore: 100,
        artistScore: 100,
        durationScore: 50,
        albumScore: 50,
        overallScore: score,
        rejectionReason: nil
    )
    return EvaluatedLyricsCandidate(lyrics: lyrics, evaluation: evaluation, arrivalIndex: arrivalIndex)
}

private let priority = LyricsCandidateRankingConfiguration(
    sourcePriorityEnabled: true,
    sourcePriorityOrder: ["QQMusic", "NetEase", "Kugou"],
    nearEqualSourcePriorityWindow: 2
)

@Suite("Near-Equal Source Priority Window")
struct NearEqualSourcePriorityWindowTests {
    @Test("Preferred source wins when its score is within the window")
    func preferredWithinWindow() {
        let better = candidate(score: 98, service: "NetEase", arrivalIndex: 0)
        let preferred = candidate(score: 97, service: "QQMusic", arrivalIndex: 1)
        let ranked = ranker.rankedCandidates([better, preferred], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["QQMusic", "NetEase"])
    }

    @Test("Preferred source loses when its score is outside the window")
    func preferredOutsideWindow() {
        let better = candidate(score: 99, service: "NetEase", arrivalIndex: 0)
        let preferred = candidate(score: 96, service: "QQMusic", arrivalIndex: 1)
        let ranked = ranker.rankedCandidates([better, preferred], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["NetEase", "QQMusic"])
    }

    @Test("Chained near-equal scores never let a candidate jump more than the window", arguments: [
        [0, 1, 2], [2, 1, 0], [1, 0, 2], [0, 2, 1],
    ])
    func chainIsConsistent(order: [Int]) {
        // 84 ≈ 82 ≈ 80 pairwise, but 80 is 4 points below 84.
        let all = [
            candidate(score: 84, service: "Kugou", arrivalIndex: 0),
            candidate(score: 82, service: "NetEase", arrivalIndex: 1),
            candidate(score: 80, service: "QQMusic", arrivalIndex: 2),
        ]
        let ranked = ranker.rankedCandidates(order.map { all[$0] }, mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["NetEase", "Kugou", "QQMusic"])
    }

    @Test("Source priority never crosses tiers")
    func tierDominates() {
        let exact = candidate(score: 96, service: "Kugou", arrivalIndex: 0)
        let strong = candidate(score: 95, service: "QQMusic", tier: .strongTitleArtist, arrivalIndex: 1)
        let ranked = ranker.rankedCandidates([strong, exact], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["Kugou", "QQMusic"])
    }

    @Test("Artist-only duplicates: near-equal preferred source first, regardless of input order", arguments: [
        [0, 1, 2], [2, 1, 0], [1, 2, 0],
    ])
    func artistOnlyConsistent(order: [Int]) {
        let mode = LyricsSearchMode.artistOnly(artist: "Olivia Rodrigo")
        let all = [
            candidate(score: 84, service: "Kugou", tier: .exactArtistCatalog, mode: mode, arrivalIndex: 0),
            candidate(score: 82, service: "NetEase", tier: .exactArtistCatalog, mode: mode, arrivalIndex: 1),
            candidate(score: 80, service: "QQMusic", tier: .exactArtistCatalog, mode: mode, arrivalIndex: 2),
        ]
        let ranked = ranker.rankedCandidates(order.map { all[$0] }, mode: mode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["NetEase", "Kugou", "QQMusic"])
    }
}

@Suite("Karaoke Preference Under Source Priority")
struct KaraokePreferenceUnderSourcePriorityTests {
    @Test("Karaoke on a less preferred source ranks first whether it scores just below or above line-synced", arguments: [
        (karaoke: 97.0, lineSynced: 98.0),
        (karaoke: 98.0, lineSynced: 97.0),
    ])
    func karaokeFirstEitherWay(scores: (karaoke: Double, lineSynced: Double)) {
        let lineSynced = candidate(score: scores.lineSynced, service: "QQMusic", arrivalIndex: 0)
        let karaoke = candidate(score: scores.karaoke, service: "Kugou", syncKind: .karaoke, arrivalIndex: 1)
        let ranked = ranker.rankedCandidates([lineSynced, karaoke], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["Kugou", "QQMusic"])
    }

    @Test("Raising a karaoke score never lowers its rank")
    func karaokeRankIsMonotonic() {
        let ranks = stride(from: 80.0, through: 100.0, by: 0.5).map { score in
            let all = [
                candidate(score: 95, service: "QQMusic", arrivalIndex: 0),
                candidate(score: 93.5, service: "NetEase", arrivalIndex: 1),
                candidate(score: score, service: "Kugou", syncKind: .karaoke, arrivalIndex: 2),
            ]
            let ranked = ranker.rankedCandidates(all, mode: titleMode, configuration: priority)
            return ranked.firstIndex { $0.evaluation.syncKind == .karaoke } ?? -1
        }
        #expect(ranks == ranks.sorted(by: >))
    }

    @Test("Preferred source can't lift a karaoke result over a much better karaoke result")
    func sourcePriorityAmongKaraokeKeepsTheWindow() {
        let lineSynced = candidate(score: 98, service: "Kugou", arrivalIndex: 0)
        let betterKaraoke = candidate(score: 97, service: "NetEase", syncKind: .karaoke, arrivalIndex: 1)
        let worseKaraoke = candidate(score: 89, service: "QQMusic", syncKind: .karaoke, arrivalIndex: 2)
        let ranked = ranker.rankedCandidates([lineSynced, worseKaraoke, betterKaraoke], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["NetEase", "QQMusic", "Kugou"])
    }

    @Test("Karaoke trailing by more than the window competes with line-synced on score")
    func karaokeOutsideWindowIsOrdinary() {
        let lineSynced = candidate(score: 98, service: "Kugou", arrivalIndex: 0)
        let karaoke = candidate(score: 87, service: "QQMusic", syncKind: .karaoke, arrivalIndex: 1)
        let ranked = ranker.rankedCandidates([karaoke, lineSynced], mode: titleMode, configuration: priority)
        #expect(ranked.map(\.lyrics.metadata.service) == ["Kugou", "QQMusic"])
    }
}

@Suite("Karaoke Promotion Baseline")
struct KaraokePromotionBaselineTests {
    @Test("Promotion compares against the best line-synced score in the same tier")
    func sameTierBaseline() {
        let noPriority = LyricsCandidateRankingConfiguration(sourcePriorityEnabled: false, karaokePreferenceWindow: 10)
        let exactLineSynced = candidate(score: 100, service: "A", arrivalIndex: 0)
        let strongLineSynced = candidate(score: 94, service: "B", tier: .strongTitleArtist, arrivalIndex: 1)
        let strongKaraoke = candidate(score: 88, service: "C", tier: .strongTitleArtist, syncKind: .karaoke, arrivalIndex: 2)
        let ranked = ranker.rankedCandidates(
            [exactLineSynced, strongLineSynced, strongKaraoke],
            mode: titleMode,
            configuration: noPriority
        )
        #expect(ranked.map(\.lyrics.metadata.service) == ["A", "C", "B"])
    }
}
