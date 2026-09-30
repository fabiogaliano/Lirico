import Foundation

/// Maps between time into a line and character positions for word-timed (karaoke)
/// lines, from the line's inline time tags. Tags are ascending by `index` and `time`,
/// with `time` measured from the line's start.
public enum KaraokeTiming {
    public typealias Tag = LyricsLine.Attachments.InlineTimeTag.Tag

    /// The UTF-16 character the fill has reached `elapsed` seconds into the line.
    /// At each tag's `time` the fill sits at that tag's `index`; between tags it is
    /// interpolated, and it is clamped to the first and last tag outside them.
    public static func sungCharacters(elapsed: TimeInterval, tags: [Tag]) -> Int {
        guard let first = tags.first else { return 0 }
        if elapsed <= first.time { return first.index }
        for i in 1 ..< tags.count {
            let prev = tags[i - 1]
            let cur = tags[i]
            if elapsed < cur.time {
                let span = cur.time - prev.time
                guard span > 0 else { return cur.index }
                let frac = (elapsed - prev.time) / span
                return prev.index + Int((Double(cur.index - prev.index) * frac).rounded())
            }
        }
        return tags.last!.index
    }

    /// Time into the line at which the word containing `character` starts: the time of
    /// the last tag at or before it, or 0 when it precedes every tag.
    public static func wordStart(atCharacter character: Int, tags: [Tag]) -> TimeInterval {
        tags.last { $0.index <= character }?.time ?? 0
    }
}
