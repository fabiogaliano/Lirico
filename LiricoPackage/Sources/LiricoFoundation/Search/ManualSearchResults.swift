import Foundation

/// Everything one manual search has returned so far, and which of it the user is offered.
public struct ManualSearchResults {
    private let mode: LyricsSearchMode
    private var candidates: [EvaluatedLyricsCandidate] = []
    private let ranker = LyricsCandidateRanker()

    public init(mode: LyricsSearchMode) {
        self.mode = mode
    }

    public mutating func append(_ batch: [EvaluatedLyricsCandidate]) {
        candidates.append(contentsOf: batch)
    }

    /// Ranked candidates to list: likely ones first, then the unlikely ones when
    /// `includeUnlikely`. Rejected candidates (a different song) are never offered.
    public func offered(includeUnlikely: Bool, configuration: LyricsCandidateRankingConfiguration) -> [EvaluatedLyricsCandidate] {
        let ranked = ranker.rankedCandidates(candidates, mode: mode, configuration: configuration)
        let likely = ranked.filter { $0.evaluation.visibility != .unlikely }
        guard includeUnlikely else { return likely }
        return likely + ranked.filter { $0.evaluation.visibility == .unlikely }
    }

    /// How many results are only listed on request.
    public var unlikelyCount: Int {
        candidates.count { $0.evaluation.visibility == .unlikely }
    }

    /// Restoration evidence to keep beside `selected` when the user applies it.
    public func supportingLyrics(excluding selected: Lyrics) -> [Lyrics] {
        SupportingLyrics.select(from: candidates, excluding: selected)
    }
}
