import Foundation

/// Typed view of the player-selection and app-lifecycle slice of `UserDefaults`.
///
/// Read by `PlayerLifecycle`, `MusicPlayers.Selected`, and the player-related preferences.
struct PlayerSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when Lirico should follow the players' lifecycle: launch when any
    /// supported player starts, quit once the last one quits.
    var launchAndQuitWithPlayer: Bool {
        get { defaults[.launchAndQuitWithPlayer] }
        nonmutating set { defaults[.launchAndQuitWithPlayer] = newValue }
    }

    /// True when the player should be Apple's system-wide now playing source
    /// instead of the scriptable players Lirico picks between automatically.
    var useSystemWideNowPlaying: Bool {
        defaults[.useSystemWideNowPlaying]
    }

    /// Bundle identifiers allowed when `useSystemWideNowPlaying` is enabled.
    var systemWideNowPlayingAppList: [String] {
        get { defaults[.systemWideNowPlayingAppList] }
        nonmutating set { defaults[.systemWideNowPlayingAppList] = newValue }
    }
}
