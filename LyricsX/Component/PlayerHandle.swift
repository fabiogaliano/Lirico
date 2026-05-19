import Combine
import Foundation
import MusicPlayer

/// The subset of the upstream `MusicPlayerProtocol` surface that LyricsX actually uses.
///
/// Injected into every consumer so the player dependency is explicit at construction
/// or setter-time. The protocol exists to (a) document the actual API surface used by
/// the app in one place and (b) eliminate the module-level `selectedPlayer` global.
///
/// `MusicPlayers.Selected` already satisfies every member except `designatedPlayerBundleID`,
/// which hides the `as? MusicPlayers.Scriptable` cast that LyricsSession used to do inline.
protocol PlayerHandle: AnyObject {
    var name: MusicPlayerName? { get }
    var currentTrack: MusicTrack? { get }
    var playbackState: PlaybackState { get }
    var playbackTime: TimeInterval { get set }

    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { get }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { get }

    /// Bundle ID of the underlying scriptable player, if any. Used to match
    /// against the terminated-app notification for "quit with player".
    var designatedPlayerBundleID: String? { get }

    func playPause()
    func skipToNextItem()
    func skipToPreviousItem()
}

extension MusicPlayers.Selected: PlayerHandle {
    var designatedPlayerBundleID: String? {
        (designatedPlayer as? MusicPlayers.Scriptable)?.playerBundleID
    }
}
