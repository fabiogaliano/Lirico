import Combine
import Foundation
import GenericID
import LiricoFoundation

/// Typed view of the search-policy slice of `UserDefaults`.
///
/// Owns the keys that decide which lyrics candidates make it through search:
/// source-priority ordering and the optional Musixmatch credential. The source preferences, `LyricsSearchPipeline`,
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

    /// Source names the search pipeline queries with these settings, from the same
    /// descriptors it builds its providers from, so priority entries and candidate
    /// source names always match. Musixmatch is included only with a token.
    var availableSources: [String] {
        makeProviderDescriptors(musixmatchToken: musixmatchToken).map(\.source)
    }

    /// Drop sources that no longer exist from the saved priority order and append new ones.
    func normalizeSourcePriorityOrder() {
        sourcePriorityOrder = normalizedSourceOrder(sourcePriorityOrder, known: availableSources)
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
    /// `LyricsCandidateRanker`. The scoring windows aren't user preferences, so
    /// they keep the configuration's defaults.
    var rankingConfiguration: LyricsCandidateRankingConfiguration {
        LyricsCandidateRankingConfiguration(
            sourcePriorityEnabled: sourcePriorityEnabled,
            sourcePriorityOrder: sourcePriorityOrder
        )
    }
}
