import Foundation

// MARK: - LyricsSearchQuery

/// A provider request together with the terms its candidates are judged against.
public struct LyricsSearchQuery: Sendable {
    public let request: LyricsSearchRequest
    public let mode: LyricsSearchMode
    public let requestedDuration: TimeInterval?
    public let requestedAlbum: String?

    /// The query an automatic search runs for the playing track. The album goes to the
    /// providers too, so ones like LRCLIB can attempt an exact-match lookup.
    public static func automatic(title: String, artist: String, album: String?, duration: TimeInterval?) -> Self {
        var userInfo: [String: String] = [:]
        if let album, !album.isEmpty {
            userInfo[LyricsSearchRequest.UserInfoKey.albumName] = album
        }
        return Self(
            request: LyricsSearchRequest(
                searchTerm: .info(title: title, artist: artist),
                duration: duration ?? 0,
                limit: 5,
                userInfo: userInfo
            ),
            mode: .titleAndArtist(title: title, artist: artist),
            requestedDuration: duration,
            requestedAlbum: album
        )
    }

    /// The query for a search the user typed. It searches by whichever of title and
    /// artist is filled in, and leaves out the album so it doesn't over-constrain the
    /// user's own terms. Nil when both are blank.
    public static func manual(title: String, artist: String, duration: TimeInterval?) -> Self? {
        let title = title.trimmingCharacters(in: .whitespaces)
        let artist = artist.trimmingCharacters(in: .whitespaces)
        let mode: LyricsSearchMode
        let searchTerm: LyricsSearchRequest.SearchTerm
        switch (title.isEmpty, artist.isEmpty) {
        case (false, false):
            mode = .titleAndArtist(title: title, artist: artist)
            searchTerm = .info(title: title, artist: artist)
        case (false, true):
            mode = .titleOnly(title: title)
            searchTerm = .keyword(title)
        case (true, false):
            mode = .artistOnly(artist: artist)
            searchTerm = .keyword(artist)
        case (true, true):
            return nil
        }
        return Self(
            request: LyricsSearchRequest(searchTerm: searchTerm, duration: duration ?? 0, limit: 8),
            mode: mode,
            requestedDuration: duration,
            requestedAlbum: nil
        )
    }
}

// MARK: - AutomaticAcceptancePolicy

/// Which remote candidates an automatic search may put on screen.
public enum AutomaticAcceptancePolicy: Sendable {
    /// Any candidate the ranker picks, including eligible loose fallbacks.
    case normal
    /// Line-synced local lyrics are already showing: only a materially better remote
    /// candidate may replace them (see `shouldRemoteUpgradeLocal`).
    case localUpgradeOnly(local: LyricsCandidateEvaluation)
}

// MARK: - AutomaticLyricsSelection

/// Decides, as candidates stream in for one track, what an automatic search shows.
///
/// Every arrival re-ranks everything collected so far, so karaoke preference and source
/// priority apply from the first result rather than only at the end.
public struct AutomaticLyricsSelection {
    public enum Decision {
        /// A better candidate than anything shown so far. Display only; not persisted.
        case interim(Lyrics)
        /// More same-song alternates arrived to use as explicit-word restoration evidence.
        case supporting([Lyrics])
        /// The search is over. `accepted` is nil when the displayed lyrics should stay.
        case finished(accepted: Lyrics?, supporting: [Lyrics])
    }

    /// How long an automatic search waits for providers before settling on what it has.
    public static let deadline: Duration = .seconds(15)

    public private(set) var candidates: [EvaluatedLyricsCandidate] = []
    private let mode: LyricsSearchMode
    private let policy: AutomaticAcceptancePolicy
    private let configuration: LyricsCandidateRankingConfiguration
    private let ranker = LyricsCandidateRanker()

    public init(mode: LyricsSearchMode, policy: AutomaticAcceptancePolicy, configuration: LyricsCandidateRankingConfiguration) {
        self.mode = mode
        self.policy = policy
        self.configuration = configuration
    }

    /// Records `candidate` and returns what changed: fresh supporting evidence whenever an
    /// acceptable best exists, and that best as `.interim` unless it's already `displayed`.
    public mutating func add(_ candidate: EvaluatedLyricsCandidate, displayed: Lyrics?) -> [Decision] {
        candidates.append(candidate)
        guard let best = acceptableBest() else { return [] }
        var decisions: [Decision] = [.supporting(SupportingLyrics.select(from: candidates, excluding: best.lyrics))]
        if displayed !== best.lyrics {
            decisions.append(.interim(best.lyrics))
        }
        return decisions
    }

    /// The final decision. Supporting evidence is computed against whatever ends up on
    /// screen: the accepted candidate, or `displayed` when none is accepted.
    public func finish(displayed: Lyrics?) -> Decision {
        let accepted = acceptableBest()?.lyrics
        return .finished(
            accepted: accepted,
            supporting: SupportingLyrics.select(from: candidates, excluding: accepted ?? displayed)
        )
    }

    private func acceptableBest() -> EvaluatedLyricsCandidate? {
        guard let best = ranker.bestCandidate(from: candidates, mode: mode, configuration: configuration) else {
            return nil
        }
        switch policy {
        case .normal:
            return best
        case .localUpgradeOnly(let local):
            return shouldRemoteUpgradeLocal(candidate: best.evaluation, local: local, configuration: configuration)
                ? best : nil
        }
    }
}

// MARK: - SupportingLyrics

/// Same-song alternates kept beside the chosen lyrics as explicit-word restoration evidence.
public enum SupportingLyrics {
    /// A handful is plenty for cross-candidate consensus; more only adds memory and noise.
    public static let limit = 10

    /// Normal-visibility candidates only (never loose-fallback or wrong-song ones),
    /// without `selected`, bounded.
    public static func select(from candidates: [EvaluatedLyricsCandidate], excluding selected: Lyrics?) -> [Lyrics] {
        bounded(candidates.filter { $0.evaluation.visibility == .normal }.map(\.lyrics), excluding: selected)
    }

    /// `lyrics` without `selected` or repeats, in order, capped at `limit`.
    public static func bounded(_ lyrics: [Lyrics], excluding selected: Lyrics?) -> [Lyrics] {
        var result: [Lyrics] = []
        for item in lyrics {
            if let selected, item === selected { continue }
            if result.contains(where: { $0 === item }) { continue }
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }
}
