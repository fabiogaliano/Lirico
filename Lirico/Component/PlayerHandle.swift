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

/// Detects the one failure that otherwise looks exactly like "nothing is playing":
/// the user declined (or later revoked) Lirico's Automation access to their player.
enum AutomationPermission {
    /// Players Lirico drives over Apple Events, checked when no single player is designated (Auto).
    private static let scriptablePlayerBundleIDs = [
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
