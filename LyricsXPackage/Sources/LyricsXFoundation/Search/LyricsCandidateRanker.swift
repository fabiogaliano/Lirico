import Foundation

// MARK: - LyricsCandidateRankingConfiguration

/// Tunable constants for the collection ranker.
///
/// These default values implement the plan's recommended thresholds.
/// App-side code (`SearchSettings`) should expose a mapper that reads
/// user preferences and produces a `LyricsCandidateRankingConfiguration`.
public struct LyricsCandidateRankingConfiguration: Equatable, Sendable {
    /// Whether source priority ordering should be applied at all.
    public var sourcePriorityEnabled: Bool
    /// Ordered list of source names from most to least preferred.
    /// Sources not in the list are sorted after listed sources.
    public var sourcePriorityOrder: [String]
    /// A karaoke candidate may beat the best line-synced result only when its
    /// `overallScore` is within this many points of the line-synced result.
    public var karaokePreferenceWindow: Double
    /// Source priority is applied only when two candidates' `overallScore`
    /// values differ by at most this many points and they share the same
    /// tier/visibility/syncKind outcome.
    public var nearEqualSourcePriorityWindow: Double
    /// Automatic search may select a loose-fallback candidate only when its
    /// `overallScore` is at least this value.
    public var automaticLooseFallbackMinimumScore: Double

    public init(
        sourcePriorityEnabled: Bool = true,
        sourcePriorityOrder: [String] = [],
        karaokePreferenceWindow: Double = 10,
        nearEqualSourcePriorityWindow: Double = 2,
        automaticLooseFallbackMinimumScore: Double = 80
    ) {
        self.sourcePriorityEnabled = sourcePriorityEnabled
        self.sourcePriorityOrder = sourcePriorityOrder
        self.karaokePreferenceWindow = karaokePreferenceWindow
        self.nearEqualSourcePriorityWindow = nearEqualSourcePriorityWindow
        self.automaticLooseFallbackMinimumScore = automaticLooseFallbackMinimumScore
    }
}

// MARK: - LyricsCandidateRanker

/// Collection-aware ranker that orders evaluated candidates and applies
/// karaoke preference, loose-fallback suppression, and source priority.
///
/// This must be a collection-level operation — not a pairwise comparator —
/// because both the karaoke threshold and the loose-fallback decision depend
/// on knowing the best candidates in the full set.
public struct LyricsCandidateRanker: Sendable {
    public init() {}

    /// Returns the candidates in ranked order according to the mode and configuration.
    ///
    /// - Rejected candidates are excluded.
    /// - Loose-fallback candidates are excluded when any normal candidate exists
    ///   (title-based modes); the caller controls showing them via the mode.
    /// - Karaoke candidates are promoted when within `karaokePreferenceWindow` of the
    ///   best line-synced score for the same tier.
    /// - Source priority is applied only among near-equal candidates.
    public func rankedCandidates(
        _ candidates: [EvaluatedLyricsCandidate],
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate] {
        switch mode {
        case .titleAndArtist, .titleOnly:
            return rankTitleBased(candidates, configuration: configuration)
        case .artistOnly:
            return rankArtistOnly(candidates, configuration: configuration)
        }
    }

    /// Returns the single best candidate for automatic selection.
    ///
    /// Respects `automaticLooseFallbackMinimumScore` — loose-fallback candidates
    /// are only eligible when no normal candidate exists and the score meets the
    /// threshold.
    public func bestCandidate(
        from candidates: [EvaluatedLyricsCandidate],
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration
    ) -> EvaluatedLyricsCandidate? {
        let ranked = rankedCandidates(candidates, mode: mode, configuration: configuration)

        switch mode {
        case .titleAndArtist, .titleOnly:
            // Normal candidates are always acceptable.
            if let best = ranked.first(where: { $0.evaluation.visibility == .normal }) {
                return best
            }
            // Loose-fallback only if score meets the conservative threshold.
            return ranked.first(where: {
                $0.evaluation.visibility == .looseFallback
                    && $0.evaluation.overallScore >= configuration.automaticLooseFallbackMinimumScore
            })

        case .artistOnly:
            // For artist-only, all non-rejected normal/catalog candidates are eligible.
            return ranked.first(where: {
                $0.evaluation.visibility == .normal || $0.evaluation.visibility == .looseFallback
            })
        }
    }

    // MARK: - Title-based ranking

    private func rankTitleBased(
        _ candidates: [EvaluatedLyricsCandidate],
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate] {
        // Partition by visibility to determine loose-fallback suppression.
        let normal = candidates.filter { $0.evaluation.visibility == .normal }
        let loose = candidates.filter { $0.evaluation.visibility == .looseFallback }
        let unlikely = candidates.filter { $0.evaluation.visibility == .unlikely }
        // Rejected candidates are fully excluded from ranked output.

        // Loose-fallback rows are shown ONLY when no normal rows exist.
        // When any normal candidate exists, loose rows are suppressed entirely.
        let visibleCandidates: [EvaluatedLyricsCandidate]
        if normal.isEmpty {
            visibleCandidates = loose
        } else {
            visibleCandidates = normal
        }

        let sorted = sortTitleBased(visibleCandidates, configuration: configuration)
        let sortedUnlikely = sortTitleBased(unlikely, configuration: configuration)
        return sorted + sortedUnlikely
    }

    private func sortTitleBased(
        _ candidates: [EvaluatedLyricsCandidate],
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate] {
        // Find the best line-synced overall score to compute karaoke window.
        let bestLineSyncedScore = candidates
            .filter { $0.evaluation.syncKind == .lineSynced }
            .map { $0.evaluation.overallScore }
            .max() ?? 0

        return candidates.sorted { a, b in
            let ae = a.evaluation
            let be = b.evaluation

            // 1. Correctness tier (higher titleBasedPriority = better)
            let aPriority = ae.matchTier.titleBasedPriority
            let bPriority = be.matchTier.titleBasedPriority
            if aPriority != bPriority { return aPriority > bPriority }

            // 2. Karaoke preference within the same tier.
            //    A karaoke result may beat a line-synced result only when it is
            //    within `karaokePreferenceWindow` points of the best line-synced score.
            let aEffectiveScore = effectiveTitleScore(
                candidate: a,
                bestLineSyncedScore: bestLineSyncedScore,
                configuration: configuration
            )
            let bEffectiveScore = effectiveTitleScore(
                candidate: b,
                bestLineSyncedScore: bestLineSyncedScore,
                configuration: configuration
            )
            if aEffectiveScore != bEffectiveScore { return aEffectiveScore > bEffectiveScore }

            // 3. Overall score (tiebreaker beyond karaoke promotion)
            if ae.overallScore != be.overallScore { return ae.overallScore > be.overallScore }

            // 4. Duration tiebreaker
            if ae.durationScore != be.durationScore { return ae.durationScore > be.durationScore }

            // 5. Source priority — only for near-equal candidates and only when enabled
            if configuration.sourcePriorityEnabled,
               abs(ae.overallScore - be.overallScore) <= configuration.nearEqualSourcePriorityWindow {
                let aSourceRank = sourceRank(
                    for: a.lyrics.metadata.service,
                    in: configuration.sourcePriorityOrder
                )
                let bSourceRank = sourceRank(
                    for: b.lyrics.metadata.service,
                    in: configuration.sourcePriorityOrder
                )
                if aSourceRank != bSourceRank { return aSourceRank < bSourceRank }
            }

            // 6. Arrival order as final stable tiebreaker
            return a.arrivalIndex < b.arrivalIndex
        }
    }

    /// Computes an effective score that incorporates karaoke promotion.
    ///
    /// A karaoke result within `karaokePreferenceWindow` points of the best line-synced
    /// score floats to just above that best score, so it sorts first within the tier.
    /// When the gap exceeds the window the real score is used and the line-synced wins.
    ///
    /// The promotion only affects sort position within a tier: tier/visibility is the
    /// dominant sort key (checked before this in `sortTitleBased`), so a karaoke
    /// candidate in a lower tier cannot jump above a line-synced candidate in a higher
    /// tier via this promotion.
    private func effectiveTitleScore(
        candidate: EvaluatedLyricsCandidate,
        bestLineSyncedScore: Double,
        configuration: LyricsCandidateRankingConfiguration
    ) -> Double {
        let score = candidate.evaluation.overallScore
        if candidate.evaluation.syncKind == .karaoke {
            let gap = bestLineSyncedScore - score
            // gap must be non-negative (candidate is at most equal to best line-synced)
            // and within the configured window.
            if gap >= 0, gap <= configuration.karaokePreferenceWindow {
                // Promote to just above the best line-synced score so karaoke sorts first.
                // The epsilon (0.001) is small enough to never cross a score band boundary.
                return bestLineSyncedScore + 0.001
            }
        }
        return score
    }

    // MARK: - Artist-only ranking

    private func rankArtistOnly(
        _ candidates: [EvaluatedLyricsCandidate],
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate] {
        // Partition: catalog results (exact/loose) vs unlikely.
        let catalog = candidates.filter {
            $0.evaluation.matchTier == .exactArtistCatalog
                || $0.evaluation.matchTier == .looseArtistCatalog
        }
        let unlikely = candidates.filter { $0.evaluation.visibility == .unlikely }

        let sortedCatalog = sortArtistOnly(catalog, configuration: configuration)
        let sortedUnlikely = sortArtistOnly(unlikely, configuration: configuration)
        return sortedCatalog + sortedUnlikely
    }

    private func sortArtistOnly(
        _ candidates: [EvaluatedLyricsCandidate],
        configuration: LyricsCandidateRankingConfiguration
    ) -> [EvaluatedLyricsCandidate] {
        return candidates.sorted { a, b in
            let ae = a.evaluation
            let be = b.evaluation

            // 1. Artist catalog tier: exact before loose
            let aTierRank = ae.matchTier == .exactArtistCatalog ? 0 : 1
            let bTierRank = be.matchTier == .exactArtistCatalog ? 0 : 1
            if aTierRank != bTierRank { return aTierRank < bTierRank }

            // 2. Visibility: normal before unlikely (looseFallback not used for artist-only)
            let aVisRank = visibilityRank(ae.visibility)
            let bVisRank = visibilityRank(be.visibility)
            if aVisRank != bVisRank { return aVisRank < bVisRank }

            // 3. Normalized title A–Z (missing title sorts last)
            let aTitle = normalizedString(a.lyrics.idTags[.title] ?? "")
            let bTitle = normalizedString(b.lyrics.idTags[.title] ?? "")
            let aHasTitle = !aTitle.isEmpty
            let bHasTitle = !bTitle.isEmpty
            if aHasTitle != bHasTitle { return aHasTitle && !bHasTitle }
            if aTitle != bTitle { return aTitle < bTitle }

            // 4. Karaoke preference within the same normalized title group.
            //    There is no meaningful "best line-synced score across the whole set"
            //    here; any karaoke result beats a line-synced result for the same title.
            if ae.syncKind != be.syncKind {
                return ae.syncKind == .karaoke
            }

            // 5. Source priority among duplicates with the same title
            if configuration.sourcePriorityEnabled,
               abs(ae.overallScore - be.overallScore) <= configuration.nearEqualSourcePriorityWindow {
                let aSourceRank = sourceRank(
                    for: a.lyrics.metadata.service,
                    in: configuration.sourcePriorityOrder
                )
                let bSourceRank = sourceRank(
                    for: b.lyrics.metadata.service,
                    in: configuration.sourcePriorityOrder
                )
                if aSourceRank != bSourceRank { return aSourceRank < bSourceRank }
            }

            // 6. Arrival order
            return a.arrivalIndex < b.arrivalIndex
        }
    }
}

// MARK: - Source priority helpers

/// Returns the 0-based rank of `source` in `order` (lower = more preferred).
/// Sources not in the list receive `Int.max` so they sort after all listed sources.
private func sourceRank(for source: String?, in order: [String]) -> Int {
    guard let source else { return Int.max }
    return order.firstIndex(of: source) ?? Int.max
}

private func visibilityRank(_ visibility: LyricsCandidateVisibility) -> Int {
    switch visibility {
    case .normal:       return 0
    case .looseFallback: return 1
    case .unlikely:     return 2
    case .rejected:     return 3
    }
}
