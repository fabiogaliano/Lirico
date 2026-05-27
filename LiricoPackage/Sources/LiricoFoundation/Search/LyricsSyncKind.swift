import LyricsKit

/// Whether a lyrics candidate carries karaoke (word-level) timing.
///
/// Karaoke requires meaningful inline-timetag coverage — not just a stray
/// `[tt]` line — so detection uses both a minimum count (≥2 eligible lines
/// with timetag) and a coverage ratio (≥50% of eligible non-empty enabled
/// lines).
public enum LyricsSyncKind: Equatable, Sendable {
    case karaoke
    case lineSynced
}

extension Lyrics {
    /// Whether this lyrics object carries karaoke (word-level) timing.
    ///
    /// True when at least 2 eligible lines have `attachments.timetag` AND
    /// those tagged lines represent ≥50% of all eligible (enabled,
    /// non-empty) lines.  One stray `[tt]` line does not qualify.
    public var isKaraokeTimed: Bool {
        let eligible = lines.filter { $0.enabled && !$0.content.isEmpty }
        guard eligible.count >= 2 else { return false }
        let taggedCount = eligible.filter { $0.attachments.timetag != nil }.count
        guard taggedCount >= 2 else { return false }
        return Double(taggedCount) / Double(eligible.count) >= 0.5
    }

    /// The sync kind inferred from inline-timetag coverage.
    public var syncKind: LyricsSyncKind {
        isKaraokeTimed ? .karaoke : .lineSynced
    }
}
