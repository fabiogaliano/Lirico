import Foundation
import LiricoFoundation
import MusicPlayer
import OpenCC

/// Writes lyrics to the user's local disk (saving-path directory) and to the
/// currently playing Apple Music track via its scripting bridge.
///
/// Pulled out of the lyrics-management hub so that the session type owns
/// state, not Apple-Music-specific formatting + scripting glue.
enum LyricsPersister {
    /// Shared base name `"Title - Artist"` used by both the saving-path loader and the writer.
    /// Slashes are replaced with colons so the composed name can't escape into a subdirectory.
    static func baseName(title: String, artist: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "/", with: ":")
        let safeArtist = artist.replacingOccurrences(of: "/", with: ":")
        return "\(safeTitle) - \(safeArtist)"
    }

    /// Filename `Title - Artist.lrcx` used by both the saving-path loader and the writer.
    /// Returns nil when title or artist is missing — the caller treats this as "skip persist".
    static func fileName(for lyrics: Lyrics) -> String? {
        guard let title = lyrics.metadata.title,
              let artist = lyrics.metadata.artist else {
            return nil
        }
        return baseName(title: title, artist: artist) + ".lrcx"
    }

    /// Write `lyrics` to disk in `directory`. On success the lyrics'
    /// `metadata.localURL` is updated to the freshly written file and
    /// `metadata.needsPersist` is cleared. Failures (no fileName, unwritable
    /// directory, …) are logged and silently swallowed.
    ///
    /// The directory is resolved by `PersistenceSettings`. Passing it in
    /// rather than reading defaults here keeps this namespace defaults-free.
    static func saveToDisk(_ lyrics: Lyrics, to directory: LyricsStorageDirectory) {
        let url = directory.url
        let security = directory.requiresSecurityScope
        if security {
            guard url.startAccessingSecurityScopedResource() else {
                return
            }
        }
        defer {
            if security {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let fileManager = FileManager.default

        do {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
                if !isDir.boolValue {
                    return
                }
            } else {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }

            guard let lrcFileURL = fileName(for: lyrics).map(url.appendingPathComponent) else {
                return
            }

            if fileManager.fileExists(atPath: lrcFileURL.path) {
                try fileManager.removeItem(at: lrcFileURL)
            }
            try lyrics.description.write(to: lrcFileURL, atomically: true, encoding: .utf8)
            lyrics.metadata.localURL = lrcFileURL
            lyrics.metadata.needsPersist = false
        } catch {
            log(error.localizedDescription)
            return
        }
    }

    /// Write `lyrics` to `track` in Apple Music.
    /// No-op unless `track` came from Apple Music. The caller must check Apple Music is
    /// still playing it (`LyricsSession.canWriteToAppleMusic`): `originalTrack` is only
    /// this track's Apple Music object while Apple Music is playing it.
    /// When `overwrite` is false, existing non-empty lyrics on the track are preserved.
    ///
    /// The `settings` parameter carries the formatting policy (plain-LRC export
    /// vs. enhanced; include translation or not). Passing it in keeps this
    /// namespace defaults-free in the same shape as `saveToDisk(_:to:)`.
    static func writeToiTunes(
        _ lyrics: Lyrics,
        to track: MusicTrack,
        overwrite: Bool,
        settings: ExportSettings,
        converter: ChineseConverter?
    ) {
        guard let sbTrack = track.originalTrack,
              overwrite || (sbTrack.value(forKey: "lyrics") as! String?)?.isEmpty != false else {
            return
        }

        let text = AppleMusicExport.text(
            for: lyrics,
            plainLRC: settings.convertToPlainLRC,
            includeTranslation: settings.writeWithTranslation,
            converter: converter?.convert
        )
        sbTrack.setValue(text, forKey: "lyrics")
    }
}
