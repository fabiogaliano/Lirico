import AppKit
import Combine
import MusicPlayer

/// Composition root for app-wide services.
///
/// `AppDelegate` constructs a single `AppContainer` after defaults registration.
/// The init body encodes the dependency graph (player → clock → session) so that
/// the previous "order matters" comment in `applicationDidFinishLaunching`
/// becomes type-level wiring instead of an informal contract.
///
/// Long-lived UI controllers will move under the container in later commits;
/// for now it just owns the lyrics services.
final class AppContainer {
    let player: PlayerHandle
    let playbackClock: PlaybackClock
    let session: LyricsSession

    init(player: PlayerHandle = MusicPlayers.Selected.shared) {
        self.player = player
        let clock = PlaybackClock(player: player)
        self.playbackClock = clock
        self.session = LyricsSession(player: player, clock: clock)
    }
}
