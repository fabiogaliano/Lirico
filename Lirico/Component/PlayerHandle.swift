import AppKit
import Combine
import Foundation
import MusicPlayer

/// The subset of the upstream `MusicPlayerProtocol` surface that Lirico actually uses.
///
/// Injected into every consumer so the player dependency is explicit at construction
/// or setter-time. The protocol exists to (a) document the actual API surface used by
/// the app in one place and (b) eliminate the module-level `selectedPlayer` global.
///
/// Reading `currentTrack` / `playbackState` after receiving an announcement returns the
/// announced value (or a later one), never the value it replaced.
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

/// The player announces a change from `willSet` on its own queue, so its properties still
/// hold the old value when subscribers run; anyone who hops queues and then re-reads them
/// can pick up the previous song or state and never hear about the new one. This adapter
/// records each announcement before passing it on, and answers reads from those records.
final class SelectedPlayerHandle: PlayerHandle {
    private let player: MusicPlayers.Selected
    // `CurrentValueSubject` stores the value before notifying and replays it on subscribe,
    // matching the `@Published` publishers it stands in for.
    private let track: CurrentValueSubject<MusicTrack?, Never>
    private let state: CurrentValueSubject<PlaybackState, Never>
    private var cancelBag = Set<AnyCancellable>()

    init(player: MusicPlayers.Selected = .shared) {
        self.player = player
        track = CurrentValueSubject(player.currentTrack)
        state = CurrentValueSubject(player.playbackState)
        player.currentTrackWillChange
            .sink { [track] in track.send($0) }
            .store(in: &cancelBag)
        player.playbackStateWillChange
            .sink { [state] in state.send($0) }
            .store(in: &cancelBag)
    }

    var name: MusicPlayerName? { player.name }
    var currentTrack: MusicTrack? { track.value }
    var playbackState: PlaybackState { state.value }

    var playbackTime: TimeInterval {
        get { state.value.time }
        set { player.playbackTime = newValue }
    }

    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { track.eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { state.eraseToAnyPublisher() }

    var designatedPlayerBundleID: String? {
        (player.designatedPlayer as? MusicPlayers.Scriptable)?.playerBundleID
    }

    func playPause() { player.playPause() }
    func skipToNextItem() { player.skipToNextItem() }
    func skipToPreviousItem() { player.skipToPreviousItem() }
}

/// Detects the one failure that otherwise looks exactly like "nothing is playing":
/// the user declined (or later revoked) Lirico's Automation access to their player.
enum AutomationPermission {
    /// Players Lirico drives over Apple Events, checked when no single player is designated (Auto).
    static let scriptablePlayerBundleIDs = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client", "com.coppertino.Vox",
        "com.audirvana.Audirvana-Studio", "com.audirvana.Audirvana", "com.audirvana.Audirvana-Plus",
        "com.audirvana.Audirvana-Origin", "com.swinsian.Swinsian",
    ]

    /// Name of a running player that Lirico is not allowed to automate, if any. Never prompts.
    static func deniedPlayerName(designatedBundleID: String?) -> String? {
        let candidates = designatedBundleID.map { [$0] } ?? scriptablePlayerBundleIDs
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, candidates.contains(bundleID) else { continue }
            var address = AEAddressDesc()
            let bytes = Array(bundleID.utf8)
            guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &address) == noErr else { continue }
            defer { AEDisposeDesc(&address) }
            let status = AEDeterminePermissionToAutomateTarget(&address, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
            if status == OSStatus(errAEEventNotPermitted) {
                return app.localizedName ?? bundleID
            }
        }
        return nil
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
