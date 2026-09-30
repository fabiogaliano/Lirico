import Foundation
import LXMusicPlayer
import MusicPlayer

/// The players Lirico drives over Apple Events, and the rules for following them.
public enum ScriptablePlayers {
    /// Every bundle ID a scriptable player can run under. LiricoHelper keeps its own copy
    /// (it doesn't link this package), so a change here has to be made there too.
    public static let bundleIDs: [String] = MusicPlayerName.scriptableCases.flatMap {
        LXScriptingMusicPlayer.Name(rawValue: $0.rawValue).candidateBundleID()
    }

    /// Auto mode's pick, as an index into `states`. Stick with `current` while it plays;
    /// otherwise follow whichever player is playing, then whichever is paused, so pausing
    /// briefly never hands lyrics to another app. Nil when every player is stopped.
    public static func autoChoice(current: Int?, states: [PlaybackState]) -> Int? {
        if let current, states[current].isPlaying {
            return current
        }
        if let playing = states.firstIndex(where: \.isPlaying) {
            return playing
        }
        if let current, states[current] != .stopped {
            return current
        }
        return states.firstIndex { $0 != .stopped }
    }

    /// Whether "quit with player" should end Lirico now that `bundleID` has quit. The
    /// player is picked automatically, so only the last supported one to quit counts.
    public static func isLastToQuit(_ bundleID: String, stillRunning: [String]) -> Bool {
        bundleIDs.contains(bundleID) && !stillRunning.contains(where: bundleIDs.contains)
    }
}
