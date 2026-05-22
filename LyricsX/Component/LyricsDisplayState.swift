import Foundation
import LyricsXFoundation

/// Pre-rendered display data for the currently active lyric line.
///
/// Computed once by `LyricsDisplayCoordinator` so each surface stops re-deriving
/// the same `LineRenderer.render(...)` calls and timetag lookups. Surfaces just
/// pick the fields they care about.
struct LyricsDisplayLine {
    let lyrics: Lyrics
    let index: Int
    let line: LyricsLine
    let nextEnabledLine: LyricsLine?

    /// Main-line text after Chinese conversion.
    let primaryText: String
    /// Translation text after Chinese conversion, when a translation
    /// attachment exists under `translationLanguageCode`.
    let translationText: String?
    /// Next-enabled-line text after Chinese conversion — used by the
    /// desktop karaoke surface as the second visible row.
    let nextLineText: String?

    /// How long the active line is expected to remain on screen. Falls back
    /// to the gap to the next line, then to 2s. Used by the menu-bar marquee.
    let duration: TimeInterval
    let translationLanguageCode: String?
}

/// A single resolved view of "what should the lyric surfaces be doing right now".
///
/// Published whenever lyrics, line index, playback state, or
/// `disableLyricsWhenPaused` change. Surfaces map this to UI; suppression
/// policy is decided here, not in each controller.
struct LyricsDisplaySnapshot {
    /// The active-line snapshot, or nil when there is no current line.
    let line: LyricsDisplayLine?

    /// True when the user has `disableLyricsWhenPaused` on and playback is
    /// paused. Surfaces that hide while paused should treat this as
    /// "do not render the line right now".
    let isPausedAndHidden: Bool

    /// There is an active line and pause-suppression is not engaged. The
    /// preferred read for surfaces that hide while paused (Karaoke / MenuBar).
    var isLive: Bool { line != nil && !isPausedAndHidden }

    static let empty = LyricsDisplaySnapshot(line: nil, isPausedAndHidden: false)
}
