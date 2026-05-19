import Combine
import Foundation
import LyricsXFoundation
import MusicPlayer

/// The time-adjusted position into the current lyrics file (playbackTime + adjustedTimeDelay).
/// This is the coordinate space used by `ScrollLyricsView` and karaoke timetag arithmetic.
typealias LyricsPosition = TimeInterval

/// PlaybackClock centralises the single concept "given current lyrics + playback state,
/// which line is active and where are we inside it?"
///
/// It drives `AppController.currentLineIndex` and exposes `adjustedPlaybackTime` so that
/// display layers (HUD scroll view, karaoke timetags) can read the offset-corrected position
/// without recomputing it themselves.
///
/// The self-scheduling loop (re-fire at next line boundary) is owned here, matching the
/// previous behaviour of `AppController.scheduleCurrentLineCheck`.
final class PlaybackClock {
    static let shared = PlaybackClock()

    // MARK: - Public interface

    /// Offset-corrected playback position in the lyrics file coordinate space.
    /// Computed live on every read so that callers see the same wall-clock-interpolated value
    /// they would have got from `selectedPlayer.playbackTime` directly.
    var adjustedPlaybackTime: TimeInterval {
        let playbackTime = MusicPlayers.Selected.shared.playbackState.time
        let delay = AppController.shared.currentLyrics?.adjustedTimeDelay ?? 0
        return playbackTime + delay
    }

    // MARK: - Private state

    private var lineCheckSchedule: Cancellable?
    private var cancelBag = Set<AnyCancellable>()

    // The lyrics-change trigger is driven by `AppController.currentLyrics.didSet` calling
    // `scheduleCurrentLineCheck()` → `tick()`. Subscribing to `$currentLyrics` here too would
    // double-tick on every change with no benefit.
    private init() {
        selectedPlayer.playbackStateWillChange
            .signal()
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [unowned self] in self.tick() }
            .store(in: &cancelBag)
    }

    // MARK: - Core tick

    /// Recompute the current line index and schedule the next tick at the upcoming line boundary.
    func tick() {
        lineCheckSchedule?.cancel()

        guard let lyrics = AppController.shared.currentLyrics else { return }

        let playbackState = MusicPlayers.Selected.shared.playbackState
        let playbackTime = playbackState.time
        let delay = lyrics.adjustedTimeDelay

        let (index, next) = lyrics[playbackTime + delay]
        if AppController.shared.currentLineIndex != index {
            AppController.shared.currentLineIndex = index
        }

        guard let next = next, playbackState.isPlaying else { return }

        let dt = lyrics.lines[next].position - playbackTime - delay
        let q = DispatchQueue.lyricsDisplay
        lineCheckSchedule = q.schedule(
            after: q.now.advanced(by: .seconds(dt)),
            interval: .seconds(42),
            tolerance: .milliseconds(20)
        ) { [unowned self] in
            self.tick()
        }
    }
}

extension Lyrics {
    /// Convert a raw playback position to the lyrics-file coordinate space.
    func lyricsPosition(from playbackTime: TimeInterval) -> LyricsPosition {
        playbackTime + adjustedTimeDelay
    }

    /// Convert a lyrics-file coordinate back to a raw playback position (used for seeking).
    func playbackTime(from lyricsPosition: LyricsPosition) -> TimeInterval {
        lyricsPosition - adjustedTimeDelay
    }
}
