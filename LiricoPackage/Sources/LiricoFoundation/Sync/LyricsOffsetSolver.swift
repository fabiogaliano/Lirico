import Foundation

/// Pure timing math for "sync by ear".
///
/// Given a point in the lyrics' own time line (`scoreTime`) that the listener
/// has aligned to the playback "now", this produces the per-song offset (in
/// milliseconds) that makes the alignment hold.
///
/// This is deliberately the single place that turns an alignment into an offset.
/// Today the whole song shares one offset (a uniform shift). If per-region drift
/// correction is added later, the offset becomes a piecewise map built from
/// several `(scoreTime, playbackTime)` anchors — and only this type grows;
/// `PlaybackClock` keeps calling the same seam.
public enum LyricsOffsetSolver {

    /// The per-song offset, in milliseconds, that makes `scoreTime` the active
    /// lyrics position when playback is at `playbackTime`.
    ///
    /// The clock resolves lines at `playbackTime + (offset + appWide) / 1000`, so
    /// to land on `scoreTime` we need
    /// `offset / 1000 = scoreTime - playbackTime - appWide / 1000`.
    ///
    /// A positive result shows lyrics earlier (corrects lyrics that lag the
    /// audio); a negative result shows them later.
    public static func offsetMilliseconds(
        aligning scoreTime: TimeInterval,
        toPlaybackTime playbackTime: TimeInterval,
        appWideOffsetMilliseconds: Int
    ) -> Int {
        let delaySeconds = scoreTime - playbackTime
        return Int((delaySeconds * 1000).rounded()) - appWideOffsetMilliseconds
    }
}
