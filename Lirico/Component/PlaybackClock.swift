import Combine
import Foundation
import LiricoFoundation
// `Lyrics` isn't Sendable; the clock only reads the lyrics it's handed, on its queue.
@preconcurrency import LyricsCore
import MusicPlayer

/// PlaybackClock centralises the single concept "given current lyrics + playback state,
/// which line is active and where are we inside it?"
///
/// It exposes the active line index as a publisher (`lineIndexUpdates`); the lyrics
/// session subscribes and mirrors the value into its own `@Published currentLineIndex`.
/// It also exposes `adjustedPlaybackTime` so karaoke timetag progress can read
/// the offset-corrected position without recomputing it. The clock holds no reference
/// to the session type.
///
/// All mutable state is confined to `DispatchQueue.lyricsDisplay`: ticks fire there from
/// playback-state changes and line-boundary timers, so main-thread callers hop onto it
/// rather than touching the state directly. That confinement, plus the lock around the
/// song offset, is why the Sendable conformance is unchecked.
final class PlaybackClock: @unchecked Sendable {
    /// An active-line emission, tagged with the lyrics it was computed against so a
    /// subscriber can drop emissions that arrive after the lyrics were replaced.
    struct LineIndexUpdate {
        let lyrics: Lyrics
        let index: Int?
    }

    // MARK: - Public interface

    /// Offset-corrected playback position in the lyrics file coordinate space.
    /// Computed live on every read so that callers see the same wall-clock-interpolated value
    /// they would have got from the player's `playbackTime` directly.
    var adjustedPlaybackTime: TimeInterval {
        player.playbackState.time + adjustedDelay
    }

    /// The playback time at which the lyrics reach `lyricsPosition`, for seeking to a line.
    func playbackTime(atLyricsPosition lyricsPosition: TimeInterval) -> TimeInterval {
        lyricsPosition - adjustedDelay
    }

    /// The per-song offset (ms) that makes `lyricsPosition` the active position right now.
    func songOffset(aligning lyricsPosition: TimeInterval) -> Int {
        LyricsOffsetSolver.offsetMilliseconds(
            aligning: lyricsPosition,
            toPlaybackTime: player.playbackState.time,
            appWideOffsetMilliseconds: globalOffsetMilliseconds
        )
    }

    /// Emits the active line index whenever it changes, and always once after new lyrics
    /// are set. `nil` index means there is no current line (before-first-line, etc.).
    var lineIndexUpdates: AnyPublisher<LineIndexUpdate, Never> {
        lineIndexSubject.eraseToAnyPublisher()
    }

    /// Replace the lyrics the clock is computing against and re-tick. Called by the
    /// lyrics session from its `currentLyrics.didSet`.
    func setLyrics(_ lyrics: Lyrics?) {
        let offset = lyrics?.offset ?? 0
        songOffsetMilliseconds = offset
        queue.async { [self] in
            self.lyrics = lyrics
            lastEmittedIndex = .none
            tick()
        }
    }

    /// Update the captured per-song offset (ms) and re-tick. Called on the main
    /// actor by the lyrics session when the user changes the offset, so the clock
    /// never has to read `Lyrics.idTags` from its background queue.
    func updateSongOffset(_ milliseconds: Int) {
        songOffsetMilliseconds = milliseconds
        queue.async { [self] in tick() }
    }

    // MARK: - Private state

    private let player: PlayerHandle
    private let queue = DispatchQueue.lyricsDisplay
    private var lyrics: Lyrics?
    /// `.none` means nothing has been emitted for the current lyrics yet.
    private var lastEmittedIndex: Int??

    /// Per-song offset (ms), captured on the main actor whenever lyrics or the
    /// offset changes, because `Lyrics.idTags` must not be read off the main thread.
    /// It is also read from main by `adjustedPlaybackTime`, so it lives behind a lock
    /// rather than on the queue.
    private var songOffsetMilliseconds: Int {
        get { songOffsetLock.withLock { _songOffsetMilliseconds } }
        set { songOffsetLock.withLock { _songOffsetMilliseconds = newValue } }
    }
    private var _songOffsetMilliseconds = 0
    private let songOffsetLock = NSLock()

    private var globalOffsetMilliseconds: Int { defaults[.globalLyricsOffset] }

    private var adjustedDelay: TimeInterval {
        TimeInterval(songOffsetMilliseconds + globalOffsetMilliseconds) / 1000
    }
    private let lineIndexSubject = PassthroughSubject<LineIndexUpdate, Never>()
    private var lineCheckSchedule: Cancellable?
    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle) {
        self.player = player
        player.playbackStateWillChange
            .signal()
            .receive(on: queue)
            .sink { [unowned self] in self.tick() }
            .store(in: &cancelBag)
    }

    // MARK: - Core tick

    /// Recompute the current line index and schedule the next tick at the upcoming line boundary.
    private func tick() {
        dispatchPrecondition(condition: .onQueue(queue))
        lineCheckSchedule?.cancel()

        guard let lyrics else { return }

        let playbackState = player.playbackState
        let playbackTime = playbackState.time
        let delay = adjustedDelay

        let (index, next) = lyrics[playbackTime + delay]
        if lastEmittedIndex != .some(index) {
            lastEmittedIndex = .some(index)
            lineIndexSubject.send(LineIndexUpdate(lyrics: lyrics, index: index))
        }

        guard let next = next, playbackState.isPlaying else { return }

        let dt = lyrics.lines[next].position - playbackTime - delay
        lineCheckSchedule = queue.schedule(
            after: queue.now.advanced(by: .seconds(dt)),
            interval: .seconds(42),
            tolerance: .milliseconds(20)
        ) { [unowned self] in
            self.tick()
        }
    }
}
