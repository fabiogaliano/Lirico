import Foundation
import Testing
@testable import LiricoFoundation

@Suite struct LyricsOffsetSolverTests {

    @Test func lineLaterThanPlaybackYieldsPositiveOffset() {
        // Heard a line whose score time is 30s while playback is at 28s: the
        // lyrics lag the audio, so they must be pulled 2s earlier.
        let ms = LyricsOffsetSolver.offsetMilliseconds(
            aligning: 30, toPlaybackTime: 28, appWideOffsetMilliseconds: 0
        )
        #expect(ms == 2000)
    }

    @Test func lineEarlierThanPlaybackYieldsNegativeOffset() {
        let ms = LyricsOffsetSolver.offsetMilliseconds(
            aligning: 28, toPlaybackTime: 30, appWideOffsetMilliseconds: 0
        )
        #expect(ms == -2000)
    }

    @Test func perfectAlignmentIsZero() {
        let ms = LyricsOffsetSolver.offsetMilliseconds(
            aligning: 42, toPlaybackTime: 42, appWideOffsetMilliseconds: 0
        )
        #expect(ms == 0)
    }

    @Test func appWideBaselineIsCompensatedSoCombinedDelayMatches() {
        // With a +500ms app-wide baseline already applied to every song, the
        // per-song offset is reduced so the *combined* delay still lands on the
        // aligned point (2000ms total).
        let ms = LyricsOffsetSolver.offsetMilliseconds(
            aligning: 30, toPlaybackTime: 28, appWideOffsetMilliseconds: 500
        )
        #expect(ms == 1500)
        #expect(ms + 500 == 2000)
    }

    @Test func roundsToNearestMillisecond() {
        let ms = LyricsOffsetSolver.offsetMilliseconds(
            aligning: 1.23449, toPlaybackTime: 0, appWideOffsetMilliseconds: 0
        )
        #expect(ms == 1234)
    }
}
