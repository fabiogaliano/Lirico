import Combine
import Foundation
import GenericID

/// Typed view of the search-policy slice of `UserDefaults`.
///
/// Owns the keys that decide which lyrics candidates make it through search:
/// strict matching, source-priority ordering, the per-search collection window,
/// and the optional Musixmatch credential. `LyricsSelector`, `LyricsSearchPipeline`,
/// and the session's automatic-search loop consume one of these rather than
/// reaching back into the flat `defaults[...]` namespace.
struct SearchSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When true, candidates that fail `Lyrics.isMatched()` are dropped before
    /// reaching the selection logic.
    var strictSearchEnabled: Bool {
        defaults[.strictSearchEnabled]
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

    /// Seconds the automatic-search loop keeps collecting candidates after
    /// accepting the first match. Defaults to 5 when unset.
    var priorityWindow: TimeInterval {
        defaults[.lyricsPriorityWindow] ?? 5
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
