import Combine
import Foundation
import GenericID
import LyricsXFoundation

/// Typed view of the search-policy slice of `UserDefaults`.
///
/// Owns the keys that decide which lyrics candidates make it through search:
/// source-priority ordering, the per-search collection window, and the
/// optional Musixmatch credential. `LyricsSelector`, `LyricsSearchPipeline`,
/// and the session's automatic-search loop consume one of these rather than
/// reaching back into the flat `defaults[...]` namespace.
struct SearchSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When true, candidates are compared by configured source order first,
    /// quality second; when false, quality alone decides.
    var sourcePriorityEnabled: Bool {
        get { defaults[.lyricsSourcePriorityEnabled] }
        nonmutating set { defaults[.lyricsSourcePriorityEnabled] = newValue }
    }

    /// User-ordered source name list. Returns an empty array when unset so
    /// callers don't have to unwrap.
    var sourcePriorityOrder: [String] {
        get { defaults[.lyricsSourcePriorityOrder] ?? [] }
        nonmutating set { defaults[.lyricsSourcePriorityOrder] = newValue }
    }

    /// Musixmatch user token. Nil/empty means the Musixmatch provider is not
    /// included in the active provider group.
    var musixmatchToken: String? {
        get { defaults[.musixmatchToken] }
        nonmutating set {
            // `Key<String?>` stores nil as "remove" already; trimming + the
            // empty-to-nil collapse is the caller's job.
            defaults[.musixmatchToken] = newValue
        }
    }

    /// Emits whenever the Musixmatch token changes. Used by
    /// `LyricsSearchPipeline` to rebuild its provider group when the user
    /// edits the token in Lab preferences.
    func musixmatchTokenPublisher() -> AnyPublisher<Void, Never> {
        defaults.publisher(for: [.musixmatchToken]).eraseToAnyPublisher()
    }
}

// MARK: - Ranking configuration

extension SearchSettings {
    /// Maps user preferences into the ranker configuration consumed by
    /// `LyricsCandidateRanker`.
    ///
    /// Window constants (`karaokePreferenceWindow`, `nearEqualSourcePriorityWindow`,
    /// `automaticLooseFallbackMinimumScore`) are not yet exposed as user-facing
    /// preferences; the SR-04 defaults (10 / 2 / 80) are used directly until
    /// SR-08 decides whether tuning controls are needed.
    var rankingConfiguration: LyricsCandidateRankingConfiguration {
        LyricsCandidateRankingConfiguration(
            sourcePriorityEnabled: sourcePriorityEnabled,
            sourcePriorityOrder: sourcePriorityOrder
            // karaokePreferenceWindow: 10 (SR-04 default)
            // nearEqualSourcePriorityWindow: 2 (SR-04 default)
            // automaticLooseFallbackMinimumScore: 80 (SR-04 default)
        )
    }
}
