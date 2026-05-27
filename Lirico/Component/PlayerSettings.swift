import Foundation

/// Typed view of the player-selection and app-lifecycle slice of `UserDefaults`.
///
/// Read by `HelperLifecycle`, `LyricsSession`'s quit-with-player handler,
/// `MusicPlayers.Selected`, and the player-related preferences.
struct PlayerSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Tag-encoded preferred-player choice. `-1` means "auto-detect"; positive
    /// values map to `MusicPlayerName(index:)`.
    var preferredPlayerIndex: Int {
        get { defaults[.preferredPlayerIndex] }
        nonmutating set { defaults[.preferredPlayerIndex] = newValue }
    }

    /// True when Lirico should follow the designated player's lifecycle:
    /// quit when the player quits, and re-launch the helper on app exit.
    var launchAndQuitWithPlayer: Bool {
        get { defaults[.launchAndQuitWithPlayer] }
        nonmutating set { defaults[.launchAndQuitWithPlayer] = newValue }
    }

    /// True when the auto-detected player should be Apple's system-wide now
    /// playing source instead of the scriptable-player aggregate.
    var useSystemWideNowPlaying: Bool {
        defaults[.useSystemWideNowPlaying]
    }

    /// Bundle identifiers allowed when `useSystemWideNowPlaying` is enabled.
    var systemWideNowPlayingAppList: [String] {
        get { defaults[.systemWideNowPlayingAppList] }
        nonmutating set { defaults[.systemWideNowPlayingAppList] = newValue }
    }
}
