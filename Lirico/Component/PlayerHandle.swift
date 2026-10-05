import AppKit
import Combine
import Foundation
import LiricoFoundation
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
}

/// The player announces a change from `willSet` on its own queue, so its properties still
/// hold the old value when subscribers run; anyone who hops queues and then re-reads them
/// can pick up the previous song or state and never hear about the new one. This adapter
/// records each announcement before passing it on, and answers reads from those records.
final class SelectedPlayerHandle: PlayerHandle {
    // `CurrentValueSubject` stores the value before notifying and replays it on subscribe,
    // matching the `@Published` publishers it stands in for.
    private let track: CurrentValueSubject<MusicTrack?, Never>
    private let state: CurrentValueSubject<PlaybackState, Never>
    private var cancelBag = Set<AnyCancellable>()

    /// `MusicPlayers.Selected` swaps its designated player on its own queue, so reading it
    /// through the agent from main races the swap; this copy is replaced under a lock instead.
    private var designated: MusicPlayerProtocol? {
        get { designatedLock.withLock { _designated } }
        set { designatedLock.withLock { _designated = newValue } }
    }
    private var _designated: MusicPlayerProtocol?
    private let designatedLock = NSLock()

    init(player: MusicPlayers.Selected = .shared) {
        track = CurrentValueSubject(player.currentTrack)
        state = CurrentValueSubject(player.playbackState)
        player.$designatedPlayer
            .sink { [weak self] in self?.designated = $0 }
            .store(in: &cancelBag)
        player.currentTrackWillChange
            .sink { [track] in track.send($0) }
            .store(in: &cancelBag)
        player.playbackStateWillChange
            .sink { [state] in state.send($0) }
            .store(in: &cancelBag)
    }

    var name: MusicPlayerName? { designated?.name }
    var currentTrack: MusicTrack? { track.value }
    var playbackState: PlaybackState { state.value }

    var playbackTime: TimeInterval {
        get { state.value.time }
        set { designated?.playbackTime = newValue }
    }

    var currentTrackWillChange: AnyPublisher<MusicTrack?, Never> { track.eraseToAnyPublisher() }
    var playbackStateWillChange: AnyPublisher<PlaybackState, Never> { state.eraseToAnyPublisher() }

    var designatedPlayerBundleID: String? {
        (designated as? MusicPlayers.Scriptable)?.playerBundleID
    }

    func playPause() { designated?.playPause() }
}

/// Detects the one failure that otherwise looks exactly like "nothing is playing":
/// the user declined (or later revoked) Lirico's Automation access to their player.
enum AutomationPermission {
    struct Candidate: Sendable {
        let bundleID: String
        let name: String
    }

    /// Running players whose permission matters. Without a designated player (Auto), every
    /// scriptable player is a candidate.
    @MainActor
    static func runningCandidates(designatedBundleID: String?) -> [Candidate] {
        let bundleIDs = designatedBundleID.map { [$0] } ?? ScriptablePlayers.bundleIDs
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, bundleIDs.contains(bundleID) else { return nil }
            return Candidate(bundleID: bundleID, name: app.localizedName ?? bundleID)
        }
    }

    /// Name of the first candidate Lirico is not allowed to automate, if any. Never prompts, but
    /// it waits on a reply from the system, which Apple says must not happen on the main thread.
    static func deniedPlayerName(among candidates: [Candidate]) -> String? {
        for candidate in candidates {
            var address = AEAddressDesc()
            let bytes = Array(candidate.bundleID.utf8)
            guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &address) == noErr else { continue }
            defer { AEDisposeDesc(&address) }
            let status = AEDeterminePermissionToAutomateTarget(&address, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
            if status == OSStatus(errAEEventNotPermitted) {
                return candidate.name
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
