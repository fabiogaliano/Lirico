import Foundation

// MARK: - LyricsCandidateRankingConfiguration

/// Tunable constants for the collection ranker.
public struct LyricsCandidateRankingConfiguration: Equatable, Sendable {
    /// Whether source priority ordering should be applied at all.
    public var sourcePriorityEnabled: Bool
    /// Ordered list of source names from most to least preferred.
    /// Sources not in the list are sorted after listed sources.
    public var sourcePriorityOrder: [String]
    /// In title-based modes, karaoke ranks above the line-synced results in its tier unless its
    /// `overallScore` trails the tier's best line-synced score by more than this many points.
    public var karaokePreferenceWindow: Double
    /// Source priority only reorders equally-ranked candidates (same tier, same side of the
    /// karaoke preference) that score within this many points of the best of them.
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
    /// - Rejected candidates are excluded, and unlikely ones follow all the others.
    /// - In title-based modes, loose-fallback candidates are listed only when no normal
    ///   candidate exists.
    /// - Karaoke ranks above line-synced within a tier, subject to `karaokePreferenceWindow`.
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
            // Every song in the artist's catalog is a valid pick; unlikely ones are by someone else.
            return ranked.first { $0.evaluation.visibility == .normal }
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
        // Karaoke preference is measured against the best line-synced score of the
        // candidate's own tier; a stronger tier's score says nothing about this one.
        var bestLineSyncedScoreByTier: [Int: Double] = [:]
        for candidate in candidates where candidate.evaluation.syncKind == .lineSynced {
            let tier = candidate.evaluation.matchTier.titleBasedPriority
            bestLineSyncedScoreByTier[tier] = max(bestLineSyncedScoreByTier[tier] ?? 0, candidate.evaluation.overallScore)
        }
        let preferredKaraoke = Set(candidates.filter { candidate in
            isPreferredKaraoke(
                candidate,
                bestLineSyncedScore: bestLineSyncedScoreByTier[candidate.evaluation.matchTier.titleBasedPriority],
                configuration: configuration
            )
        }.map(\.id))

        let sorted = candidates.sorted { a, b in
            let ae = a.evaluation
            let be = b.evaluation

            // 1. Correctness tier (higher titleBasedPriority = better)
            let aPriority = ae.matchTier.titleBasedPriority
            let bPriority = be.matchTier.titleBasedPriority
            if aPriority != bPriority { return aPriority > bPriority }

            // 2. Karaoke preference within the same tier.
            let aPreferred = preferredKaraoke.contains(a.id)
            let bPreferred = preferredKaraoke.contains(b.id)
            if aPreferred != bPreferred { return aPreferred }

            // 3. Overall score
            if ae.overallScore != be.overallScore { return ae.overallScore > be.overallScore }

            // 4. Duration tiebreaker
            if ae.durationScore != be.durationScore { return ae.durationScore > be.durationScore }

            // 4.5. Album tiebreaker — applied after duration because it is the weaker signal.
            //      This handles cases where band clamping erases small blend differences.
            if ae.albumScore != be.albumScore { return ae.albumScore > be.albumScore }

            // 5. Arrival order as final stable tiebreaker
            return a.arrivalIndex < b.arrivalIndex
        }

        // 6. Source priority among near-equal candidates of the same tier. Word timing
        //    matters more than which source supplied it, so priority never crosses the
        //    karaoke preference.
        return applyingSourcePriority(
            to: sorted,
            configuration: configuration,
            sameGroup: { a, b in
                a.evaluation.matchTier.titleBasedPriority == b.evaluation.matchTier.titleBasedPriority
                    && preferredKaraoke.contains(a.id) == preferredKaraoke.contains(b.id)
            }
        )
    }

    /// Whether a karaoke candidate ranks above every line-synced candidate in its tier.
    ///
    /// Only a lower bound applies: a karaoke result scoring at or above the best
    /// line-synced one must be preferred too, or a better karaoke result could rank
    /// below a worse one. Tier stays the dominant sort key, so this never lifts a
    /// karaoke candidate above a stronger tier.
    private func isPreferredKaraoke(
        _ candidate: EvaluatedLyricsCandidate,
        bestLineSyncedScore: Double?,
        configuration: LyricsCandidateRankingConfiguration
    ) -> Bool {
        guard candidate.evaluation.syncKind == .karaoke else { return false }
        guard let bestLineSyncedScore else { return true }
        return bestLineSyncedScore - candidate.evaluation.overallScore <= configuration.karaokePreferenceWindow
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
        func titleKey(_ candidate: EvaluatedLyricsCandidate) -> String {
            normalizedString(candidate.lyrics.idTags[.title] ?? "")
        }

        let sorted = candidates.sorted { a, b in
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
            let aTitle = titleKey(a)
            let bTitle = titleKey(b)
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

            // 5. Overall score among duplicates of the same title
            if ae.overallScore != be.overallScore { return ae.overallScore > be.overallScore }

            // 6. Arrival order
            return a.arrivalIndex < b.arrivalIndex
        }

        // 7. Source priority among near-equal duplicates of the same title.
        return applyingSourcePriority(
            to: sorted,
            configuration: configuration,
            sameGroup: { a, b in
                a.evaluation.matchTier == b.evaluation.matchTier
                    && a.evaluation.visibility == b.evaluation.visibility
                    && a.evaluation.syncKind == b.evaluation.syncKind
                    && titleKey(a) == titleKey(b)
            }
        )
    }

    /// Reorders an already-sorted list so that, within each run of candidates that share a
    /// group and score within `nearEqualSourcePriorityWindow` of the run's leader, the
    /// preferred source comes first.
    ///
    /// This is a pass over the sorted list rather than a comparator clause: "within N points"
    /// is not transitive (80 ≈ 82 ≈ 84 but 80 ≉ 84), so as a comparator it gives `sort` an
    /// inconsistent ordering. Anchoring each cluster on its highest-scoring member keeps the
    /// guarantee that no candidate overtakes one more than the window above it.
    private func applyingSourcePriority(
        to sorted: [EvaluatedLyricsCandidate],
        configuration: LyricsCandidateRankingConfiguration,
        sameGroup: (EvaluatedLyricsCandidate, EvaluatedLyricsCandidate) -> Bool
    ) -> [EvaluatedLyricsCandidate] {
        guard configuration.sourcePriorityEnabled, !sorted.isEmpty else { return sorted }

        var result: [EvaluatedLyricsCandidate] = []
        result.reserveCapacity(sorted.count)
        var clusterStart = 0
        while clusterStart < sorted.count {
            let leader = sorted[clusterStart]
            var clusterEnd = clusterStart + 1
            while clusterEnd < sorted.count,
                  sameGroup(leader, sorted[clusterEnd]),
                  leader.evaluation.overallScore - sorted[clusterEnd].evaluation.overallScore
                      <= configuration.nearEqualSourcePriorityWindow {
                clusterEnd += 1
            }
            let cluster = sorted[clusterStart..<clusterEnd].enumerated().sorted { lhs, rhs in
                let lhsRank = sourceRank(for: lhs.element.lyrics.metadata.service, in: configuration.sourcePriorityOrder)
                let rhsRank = sourceRank(for: rhs.element.lyrics.metadata.service, in: configuration.sourcePriorityOrder)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            result.append(contentsOf: cluster.map(\.element))
            clusterStart = clusterEnd
        }
        return result
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
