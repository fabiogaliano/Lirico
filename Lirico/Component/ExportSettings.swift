import Foundation

/// Typed view of the Apple Music / iTunes export-policy slice of `UserDefaults`.
///
/// Consumed by `LyricsPersister.writeToiTunes` and by `LyricsSession`'s
/// auto-write paths (`select`, `clear`, `currentTrackChanged`). Centralising
/// these three keys keeps the "should we push lyrics into Apple Music?" /
/// "how should we format them?" policy out of arbitrary call sites.
struct ExportSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when newly accepted lyrics should be pushed into the current
    /// Apple Music track automatically.
    var writeToiTunesAutomatically: Bool {
        defaults[.writeToiTunesAutomatically]
    }

    /// True when the exported lyrics should include the first available
    /// translation language alongside the main lines.
    var writeWithTranslation: Bool {
        defaults[.writeiTunesWithTranslation]
    }

    /// True when the export should drop enhanced LRC features and write
    /// legacy single-line-per-timestamp `.lrc` formatting instead.
    var convertToPlainLRC: Bool {
        defaults[.writeiTunesConvertToPlainLRC]
    }
}
