import Combine
import Foundation
import LiricoFoundation
import MusicPlayer

/// The time-adjusted position into the current lyrics file (playbackTime + adjustedTimeDelay).
/// This is the coordinate space used by `ScrollLyricsView` and karaoke timetag arithmetic.
typealias LyricsPosition = TimeInterval

/// PlaybackClock centralises the single concept "given current lyrics + playback state,
/// which line is active and where are we inside it?"
///
/// It exposes the current active line index as a publisher (`currentLineIndex`); the
/// lyrics session subscribes and mirrors the value into its own `@Published
/// currentLineIndex`. It also exposes `adjustedPlaybackTime` so karaoke/touchbar
/// timetag progress can read the offset-corrected position without recomputing it.
///
/// The clock is a publisher: lyrics are pushed in via `setLyrics(_:)`, and a dedup
/// hook (`dedupTarget`) lets the session report what value it has already mirrored so
/// duplicate emissions can be suppressed. The clock holds no reference to the session
/// type.
final class PlaybackClock {
    // MARK: - Public interface

    /// Offset-corrected playback position in the lyrics file coordinate space.
    /// Computed live on every read so that callers see the same wall-clock-interpolated value
    /// they would have got from the player's `playbackTime` directly.
    var adjustedPlaybackTime: TimeInterval {
        player.playbackState.time + adjustedDelay
    }

    /// Emits the current active line index whenever it changes.
    /// `nil` means there is no current line (no lyrics loaded, before-first-line, etc.).
    var currentLineIndex: AnyPublisher<Int?, Never> {
        currentLineIndexSubject.eraseToAnyPublisher()
    }

    /// Replace the lyrics the clock is computing against and re-tick. Called by the
    /// lyrics session from its `currentLyrics.didSet`.
    func setLyrics(_ lyrics: Lyrics?) {
        self.lyrics = lyrics
        songOffsetMilliseconds = lyrics?.offset ?? 0
        tick()
    }

    /// Update the captured per-song offset (ms) and re-tick. Called on the main
    /// actor by the lyrics session when the user changes the offset, so the clock
    /// never has to read `Lyrics.idTags` from its background queue.
    func updateSongOffset(_ milliseconds: Int) {
        songOffsetMilliseconds = milliseconds
        tick()
    }

    /// Returns the index the subscriber has already mirrored, so the clock can skip
    /// re-emitting an unchanged value. Defaults to `{ nil }`, which lets the first
    /// tick after construction always emit.
    var dedupTarget: () -> Int? = { nil }

    // MARK: - Private state

    private let player: PlayerHandle
    private var lyrics: Lyrics?

    /// Per-song offset (ms), captured on the main actor whenever lyrics or the
    /// offset changes. `tick()` runs on the `lyricsDisplay` queue and must not
    /// read `Lyrics.idTags` there — that would race the main-thread offset writes
    /// and tear the dictionary. A stale plain-`Int` read is harmless by contrast.
    /// The app-wide global offset is added live as a thread-safe `UserDefaults` read.
    private var songOffsetMilliseconds = 0

    private var adjustedDelay: TimeInterval {
        TimeInterval(songOffsetMilliseconds + defaults[.globalLyricsOffset]) / 1000
    }
    private let currentLineIndexSubject = CurrentValueSubject<Int?, Never>(nil)
    private var lineCheckSchedule: Cancellable?
    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle) {
        self.player = player
        player.playbackStateWillChange
            .signal()
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [unowned self] in self.tick() }
            .store(in: &cancelBag)
    }

    // MARK: - Core tick

    /// Recompute the current line index and schedule the next tick at the upcoming line boundary.
    func tick() {
        lineCheckSchedule?.cancel()

        guard let lyrics else { return }

        let playbackState = player.playbackState
        let playbackTime = playbackState.time
        let delay = adjustedDelay

        let (index, next) = lyrics[playbackTime + delay]
        if dedupTarget() != index {
            currentLineIndexSubject.send(index)
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
