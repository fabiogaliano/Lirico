import Combine
import Foundation
import GenericID

/// Typed view of the display-policy slice of `UserDefaults`.
///
/// `LyricsDisplayCoordinator` consumes one of these instead of reading the
/// global `defaults`. The wrapper isolates the policy surface (currently
/// `disableLyricsWhenPaused`) from the flat `UserDefaults.DefaultsKeys`
/// namespace so a future setting that affects display can be added here
/// without growing another global call site.
struct DisplaySettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when paused playback should hide the active lyric line.
    var disableLyricsWhenPaused: Bool {
        defaults[.disableLyricsWhenPaused]
    }

    /// Emits whenever `disableLyricsWhenPaused` is written to defaults.
    /// Erased to `AnyPublisher` so the coordinator's signature is independent
    /// of the underlying KVO-backed publisher type.
    func disableLyricsWhenPausedPublisher() -> AnyPublisher<Void, Never> {
        defaults.publisher(for: [.disableLyricsWhenPaused]).eraseToAnyPublisher()
    }
}
