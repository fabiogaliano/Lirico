// MARK: - LyricsLocalUpgradePolicy

/// Decides whether a remote candidate may replace already-displayed local
/// line-synced lyrics during automatic search.
///
/// Karaoke-timed local lyrics never reach this function: the app keeps them
/// without searching (`LocalLyrics.resolve`). It only governs the
/// line-synced-local case.
///
/// Rules (SR-07 / DEC-009):
/// - The remote candidate must be `.normal` visibility AND `.exactTitleArtist`
///   or `.strongTitleArtist` tier; otherwise NO upgrade.
/// - If the candidate is karaoke: upgrade is allowed when
///   `localScore − candidateScore ≤ karaokePreferenceWindow`.
///   A negative gap (candidate scores higher than local) always upgrades.
/// - If the candidate is line-synced: upgrade is allowed only when
///   `candidateScore ≥ localScore + 5` (materially better).
/// - Source priority cannot force a local replacement.
public func shouldRemoteUpgradeLocal(
    candidate: LyricsCandidateEvaluation,
    local: LyricsCandidateEvaluation,
    configuration: LyricsCandidateRankingConfiguration
) -> Bool {
    // Guard: candidate must be a normal, exact/strong result.
    guard candidate.visibility == .normal else { return false }
    guard candidate.matchTier == .exactTitleArtist
       || candidate.matchTier == .strongTitleArtist
    else { return false }

    switch candidate.syncKind {
    case .karaoke:
        // Replace local line-synced when remote karaoke is within the window
        // (including equal-or-better — no lower bound).
        let gap = local.overallScore - candidate.overallScore
        return gap <= configuration.karaokePreferenceWindow

    case .lineSynced:
        // Replace local line-synced only when materially better.
        return candidate.overallScore >= local.overallScore + 5
    }
}
