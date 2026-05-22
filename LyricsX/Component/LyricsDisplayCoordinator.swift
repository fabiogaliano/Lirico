import AppKit
import Combine
import LyricsXFoundation
import MusicPlayer

/// Owns the "what should each lyric surface show right now" calculation.
///
/// Inputs:
///   - `LyricsSession`'s `$currentLyrics` and `$currentLineIndex`
///   - `PlayerHandle`'s `playbackStateWillChange`
///   - The `disableLyricsWhenPaused` preference
///
/// Output: `@Published snapshot: LyricsDisplaySnapshot`. Every lyric surface
/// (desktop karaoke, menu bar, touch bar) subscribes here instead of reaching
/// back into the session's raw publishers and re-deriving render policy.
final class LyricsDisplayCoordinator {
    /// Latest resolved display state. Always assigned on the main queue so
    /// subscribers can update UI without an extra hop.
    @Published private(set) var snapshot: LyricsDisplaySnapshot = .empty

    private let player: PlayerHandle
    private let settings: DisplaySettings
    private var currentLyrics: Lyrics?
    private var currentIndex: Int?
    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle, settings: DisplaySettings = DisplaySettings()) {
        self.player = player
        self.settings = settings
    }

    /// Wire the coordinator to the session's projected publishers. Called once
    /// from `LyricsSession.init` after `super.init()`, so the coordinator can
    /// receive the `$currentLyrics` / `$currentLineIndex` projections without
    /// the session having to hand them to its own initializer.
    func observe(
        lyrics: Published<Lyrics?>.Publisher,
        index: Published<Int?>.Publisher
    ) {
        lyrics
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [weak self] value in
                self?.currentLyrics = value
                self?.recompute()
            }
            .store(in: &cancelBag)

        index
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [weak self] value in
                self?.currentIndex = value
                self?.recompute()
            }
            .store(in: &cancelBag)

        player.playbackStateWillChange
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [weak self] _ in
                self?.recompute()
            }
            .store(in: &cancelBag)

        settings.disableLyricsWhenPausedPublisher()
            .receive(on: DispatchQueue.lyricsDisplay)
            .sink { [weak self] in
                self?.recompute()
            }
            .store(in: &cancelBag)
    }

    private func recompute() {
        let next = resolveSnapshot()
        DispatchQueue.main.async { [weak self] in
            self?.snapshot = next
        }
    }

    private func resolveSnapshot() -> LyricsDisplaySnapshot {
        let isPausedAndHidden = settings.disableLyricsWhenPaused && !player.playbackState.isPlaying

        guard let lyrics = currentLyrics,
              let index = currentIndex,
              lyrics.lines.indices.contains(index) else {
            return LyricsDisplaySnapshot(line: nil, isPausedAndHidden: isPausedAndHidden)
        }

        let currentLine = lyrics.lines[index]
        let nextEnabled = lyrics.lines[(index + 1)...].first { $0.enabled }
        let languageCode = lyrics.metadata.translationLanguages.first

        let (primaryText, translationText) = LineRenderer.render(
            line: currentLine,
            lyricsLanguage: lyrics.metadata.language,
            translationLanguageCode: languageCode,
            convert: [.mainLine, .translation]
        )

        let nextLineText: String? = nextEnabled.map {
            LineRenderer.render(
                line: $0,
                lyricsLanguage: lyrics.metadata.language,
                translationLanguageCode: nil,
                convert: .mainLine
            ).content
        }

        let duration: TimeInterval
        if let timetagDuration = currentLine.attachments.timetag?.duration {
            duration = timetagDuration
        } else if (index + 1) < lyrics.lines.count {
            duration = lyrics.lines[index + 1].position - currentLine.position
        } else {
            duration = 2
        }

        let line = LyricsDisplayLine(
            lyrics: lyrics,
            index: index,
            line: currentLine,
            nextEnabledLine: nextEnabled,
            primaryText: primaryText,
            translationText: translationText,
            nextLineText: nextLineText,
            duration: duration,
            translationLanguageCode: languageCode
        )
        return LyricsDisplaySnapshot(line: line, isPausedAndHidden: isPausedAndHidden)
    }
}
