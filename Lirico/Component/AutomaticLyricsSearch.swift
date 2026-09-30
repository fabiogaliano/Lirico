import Foundation
import LiricoFoundation

// MARK: - AutomaticAcceptancePolicy

/// Governs which remote candidates are eligible to replace the current lyrics
/// during an automatic search.
///
/// `.normal`: any strong remote candidate may become `currentLyrics`.
/// `.localUpgradeOnly`: only materially-better strong remote candidates may
///  replace the already-displayed local line-synced lyrics. Evaluated local
///  score is computed once at search start and retained for comparisons.
enum AutomaticAcceptancePolicy {
    case normal
    /// An exact/strong remote candidate may replace local line-synced lyrics only
    /// when it is materially better (karaoke within window, or line-synced +5 points).
    case localUpgradeOnly(existing: Lyrics, existingEvaluation: LyricsCandidateEvaluation)
}

// MARK: - AutomaticLyricsSearch

/// Decides, for one track, which remote lyrics an automatic search should show.
///
/// It owns the provider race, ranking and acceptance policy, and reports its
/// choices as `Decision`s; `LyricsSession` owns the state those decisions are
/// applied to (current lyrics, track association, persistence, export). Keeping
/// the policy here means the session never reasons about candidates, and this
/// type never touches app state.
@MainActor
final class AutomaticLyricsSearch {
    enum Decision {
        /// A better candidate than anything shown so far. Display only; not persisted.
        case interim(Lyrics)
        /// More same-song alternates arrived to use as explicit-word restoration evidence.
        case supporting([Lyrics])
        /// The search is over. `accepted` is nil when the displayed lyrics should stay.
        case finished(accepted: Lyrics?, supporting: [Lyrics])
    }

    struct Request {
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval?
        let policy: AutomaticAcceptancePolicy
    }

    /// Upper bound on retained supporting candidates. A handful is plenty for
    /// cross-candidate consensus; more would only add memory and noise.
    nonisolated static let maxSupportingLyrics = 10

    private let pipeline: LyricsSearchPipeline
    private let searchSettings: SearchSettings
    private let deadline: Duration = .seconds(15)

    nonisolated init(pipeline: LyricsSearchPipeline, searchSettings: SearchSettings) {
        self.pipeline = pipeline
        self.searchSettings = searchSettings
    }

    /// Runs until every provider finishes or the deadline passes, whichever comes
    /// first, then reports `.finished` exactly once. Stops reporting as soon as
    /// `isCurrent` turns false (track changed, or the user picked or cleared lyrics).
    ///
    /// - Parameter displayed: the lyrics currently on screen, which supporting
    ///   evidence is computed against when no new candidate is accepted.
    func run(
        _ request: Request,
        isCurrent: @escaping @MainActor () -> Bool,
        displayed: @escaping @MainActor () -> Lyrics?,
        report: @escaping @MainActor (Decision) -> Void
    ) async {
        // Album metadata is included in automatic-track requests so providers
        // like LRCLIB can attempt an exact-match lookup (SR-02). Manual
        // searches omit album to avoid over-constraining user-initiated queries.
        var userInfo: [String: String] = [:]
        if let album = request.album, !album.isEmpty {
            userInfo[LyricsSearchRequest.UserInfoKey.albumName] = album
        }
        let searchRequest = LyricsSearchRequest(
            searchTerm: .info(title: request.title, artist: request.artist),
            duration: request.duration ?? 0,
            limit: 5,
            userInfo: userInfo
        )
        let mode: LyricsSearchMode = .titleAndArtist(title: request.title, artist: request.artist)
        let configuration = searchSettings.rankingConfiguration
        let stream = pipeline.events(
            for: searchRequest,
            mode: mode,
            requestedDuration: request.duration,
            requestedAlbum: request.album
        )

        // Both racing children run on the main actor, so sharing this is safe.
        var collected: [EvaluatedLyricsCandidate] = []
        let deadline = deadline

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await event in stream {
                    guard isCurrent() else { break }
                    guard case .candidate(let candidate) = event else { continue }
                    collected.append(candidate)
                    self.reportInterim(
                        collected: collected,
                        request: request,
                        mode: mode,
                        configuration: configuration,
                        displayed: displayed(),
                        report: report
                    )
                }
            }
            group.addTask {
                try? await Task.sleep(for: deadline)
            }
            // Whichever finishes first wins; the other is cancelled (DEC-003).
            await group.next()
            group.cancelAll()
        }

        guard isCurrent() else { return }
        let accepted = LyricsCandidateRanker()
            .bestCandidate(from: collected, mode: mode, configuration: configuration)
            .flatMap { accepts($0, policy: request.policy, configuration: configuration) ? $0.lyrics : nil }
        report(.finished(
            accepted: accepted,
            supporting: Self.supporting(from: collected, selected: accepted ?? displayed())
        ))
    }

    /// Re-ranks everything collected so far and reports the best candidate when it is
    /// acceptable and not already shown, so karaoke preference and source priority
    /// apply from the first arrival rather than only at the end.
    private func reportInterim(
        collected: [EvaluatedLyricsCandidate],
        request: Request,
        mode: LyricsSearchMode,
        configuration: LyricsCandidateRankingConfiguration,
        displayed: Lyrics?,
        report: @MainActor (Decision) -> Void
    ) {
        guard let best = LyricsCandidateRanker().bestCandidate(from: collected, mode: mode, configuration: configuration),
              accepts(best, policy: request.policy, configuration: configuration)
        else { return }
        // Refresh restoration evidence as the collection grows, even when the
        // displayed candidate itself is unchanged.
        report(.supporting(Self.supporting(from: collected, selected: best.lyrics)))
        if displayed !== best.lyrics {
            report(.interim(best.lyrics))
        }
    }

    /// `.normal` accepts same-song and eligible loose-fallback candidates (the ranker
    /// already gates loose fallback by score). `.localUpgradeOnly` defers to the
    /// package-level upgrade rule; the karaoke-local short-circuit happens before
    /// any search starts.
    private func accepts(
        _ candidate: EvaluatedLyricsCandidate,
        policy: AutomaticAcceptancePolicy,
        configuration: LyricsCandidateRankingConfiguration
    ) -> Bool {
        let visibility = candidate.evaluation.visibility
        guard visibility == .normal || visibility == .looseFallback else { return false }
        switch policy {
        case .normal:
            return true
        case .localUpgradeOnly(_, let localEvaluation):
            return shouldRemoteUpgradeLocal(
                candidate: candidate.evaluation,
                local: localEvaluation,
                configuration: configuration
            )
        }
    }

    /// Same-song alternates (normal visibility only — never loose fallback or
    /// wrong-song candidates), excluding the displayed lyrics, bounded.
    private nonisolated static func supporting(from collected: [EvaluatedLyricsCandidate], selected: Lyrics?) -> [Lyrics] {
        boundedSupporting(
            collected.filter { $0.evaluation.visibility == .normal }.map(\.lyrics),
            excluding: selected
        )
    }

    nonisolated static func boundedSupporting(_ lyrics: [Lyrics], excluding selected: Lyrics?) -> [Lyrics] {
        var result: [Lyrics] = []
        for item in lyrics {
            if let selected, item === selected { continue }
            if result.contains(where: { $0 === item }) { continue }
            result.append(item)
            if result.count >= maxSupportingLyrics { break }
        }
        return result
    }
}

// MARK: - Local lyrics evaluation

extension AutomaticLyricsSearch {
    /// Scores local line-synced lyrics so remote candidates can be compared against them.
    /// Stamps a synthetic source name into `metadata.service` for diagnostics; it is not
    /// a remote source-priority entry and doesn't take part in source ranking.
    nonisolated static func evaluateLocal(
        _ lyrics: Lyrics,
        title: String,
        artist: String,
        duration: TimeInterval?,
        album: String?,
        persistenceSettings: PersistenceSettings
    ) -> LyricsCandidateEvaluation {
        lyrics.metadata.service = localSourceName(for: lyrics, persistenceSettings: persistenceSettings)
        return LyricsCandidateEvaluator().evaluate(
            lyrics: lyrics,
            mode: .titleAndArtist(title: title, artist: artist),
            requestedDuration: duration,
            requestedAlbum: album
        )
    }

    /// "Embedded" when read from the track's own tags, "Local Storage" when saved in
    /// Lirico's directory, otherwise "Beside Track".
    private nonisolated static func localSourceName(for lyrics: Lyrics, persistenceSettings: PersistenceSettings) -> String {
        guard let localURL = lyrics.metadata.localURL else { return "Embedded" }
        return persistenceSettings.storageDirectoryContains(localURL) ? "Local Storage" : "Beside Track"
    }
}
