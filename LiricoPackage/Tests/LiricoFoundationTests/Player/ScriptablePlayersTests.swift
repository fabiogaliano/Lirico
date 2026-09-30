import MusicPlayer
import Testing
@testable import LiricoFoundation

@Suite("Scriptable players")
struct ScriptablePlayersTests {
    private let playing = PlaybackState.playing(time: 10)
    private let paused = PlaybackState.paused(time: 10)
    private let stopped = PlaybackState.stopped

    @Test func keepsTheCurrentPlayerWhileItPlays() {
        #expect(ScriptablePlayers.autoChoice(current: 1, states: [playing, playing]) == 1)
    }

    @Test func pausingHandsOverToAPlayingPlayer() {
        #expect(ScriptablePlayers.autoChoice(current: 0, states: [paused, stopped, playing]) == 2)
    }

    @Test func pausedCurrentPlayerIsKeptWhenNothingPlays() {
        #expect(ScriptablePlayers.autoChoice(current: 1, states: [paused, paused]) == 1)
    }

    @Test func withoutACurrentPlayerTheFirstNonStoppedOneIsPicked() {
        #expect(ScriptablePlayers.autoChoice(current: nil, states: [stopped, paused, paused]) == 1)
        #expect(ScriptablePlayers.autoChoice(current: 0, states: [stopped, paused]) == 1)
    }

    @Test func nothingIsPickedWhenEveryPlayerIsStopped() {
        #expect(ScriptablePlayers.autoChoice(current: 0, states: [stopped, stopped]) == nil)
        #expect(ScriptablePlayers.autoChoice(current: nil, states: []) == nil)
    }

    @Test func quitsOnlyWhenTheLastSupportedPlayerQuits() {
        #expect(ScriptablePlayers.isLastToQuit("com.spotify.client", stillRunning: ["com.apple.Safari"]))
        #expect(!ScriptablePlayers.isLastToQuit("com.spotify.client", stillRunning: ["com.apple.Music"]))
        #expect(!ScriptablePlayers.isLastToQuit("com.apple.Safari", stillRunning: []))
    }

    /// LiricoHelper launches Lirico for exactly this list; it has to be kept in step by hand.
    @Test func bundleIDsMatchTheHelpersList() {
        #expect(ScriptablePlayers.bundleIDs == [
            "com.apple.Music", "com.apple.iTunes",
            "com.spotify.client",
            "com.coppertino.Vox",
            "com.audirvana.Audirvana-Studio", "com.audirvana.Audirvana", "com.audirvana.Audirvana-Plus", "com.audirvana.Audirvana-Origin",
            "com.swinsian.Swinsian",
        ])
    }
}
