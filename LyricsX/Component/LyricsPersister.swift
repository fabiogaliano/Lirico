import Foundation
import LyricsXFoundation
import MusicPlayer
import OpenCC
import Regex

/// Writes lyrics to the user's local disk (saving-path directory) and to the
/// currently playing Apple Music track via its scripting bridge.
///
/// Pulled out of the lyrics-management hub so that the session type owns
/// state, not Apple-Music-specific formatting + scripting glue. Mirrors the
/// pattern used by `LyricsPreparer` / `LocalLyricsLoader`: a small `enum`
/// namespace of pure static functions.
enum LyricsPersister {
    /// Filename `Title - Artist.lrcx` used by both the saving-path loader and the writer.
    /// Returns nil when title or artist is missing — the caller treats this as "skip persist".
    static func fileName(for lyrics: Lyrics) -> String? {
        guard let title = lyrics.metadata.title?.replacingOccurrences(of: "/", with: ":"),
              let artist = lyrics.metadata.artist?.replacingOccurrences(of: "/", with: ":") else {
            return nil
        }
        return "\(title) - \(artist).lrcx"
    }

    /// Write `lyrics` to disk in `directory`. On success the lyrics'
    /// `metadata.localURL` is updated to the freshly written file and
    /// `metadata.needsPersist` is cleared. Failures (no fileName, unwritable
    /// directory, …) are logged and silently swallowed.
    ///
    /// The directory tuple is resolved by `PersistenceSettings`. Passing it in
    /// rather than reading defaults here keeps this namespace defaults-free.
    static func saveToDisk(_ lyrics: Lyrics, to directory: (url: URL, security: Bool)) {
        let (url, security) = directory
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

    /// Write `lyrics` to the currently playing Apple Music track.
    /// No-op if the player isn't Apple Music or there's no scriptable track.
    /// When `overwrite` is false, existing non-empty lyrics on the track are preserved.
    static func writeToiTunes(_ lyrics: Lyrics, player: PlayerHandle, overwrite: Bool) {
        guard player.name == .appleMusic,
              let sbTrack = player.currentTrack?.originalTrack,
              overwrite || (sbTrack.value(forKey: "lyrics") as! String?)?.isEmpty != false else {
            return
        }

        let content: String
        if defaults[.writeiTunesConvertToPlainLRC] {
            // For plain LRC export, preserve the legacy LRC formatting but still respect
            // the Chinese conversion setting for consistency with the non-plain branch.
            var legacy = lyrics.legacyDescription
            if let converter = ChineseConverter.shared,
               lyrics.metadata.language?.hasPrefix("zh") == true {
                legacy = converter.convert(legacy)
            }
            // Translations are intentionally not appended for plain LRC export,
            // even when `writeiTunesWithTranslation` is enabled, to keep the legacy
            // LRC output single-line per timestamp.
            content = legacy
        } else {
            // TODO: tagged translation
            let translationCode = defaults[.writeiTunesWithTranslation]
                ? lyrics.metadata.translationLanguages.first
                : nil
            content = lyrics.lines.map { line -> String in
                let (main, translation) = LineRenderer.render(
                    line: line,
                    lyricsLanguage: lyrics.metadata.language,
                    translationLanguageCode: translationCode,
                    convert: .all
                )
                if let translation {
                    return main + "\n" + translation
                }
                return main
            }.joined(separator: "\n")
        }
        // swiftlint:disable:next force_try
        let regex = Regex(#"\n{3,}"#)
        let replaced = content.replacingMatches(of: regex, with: "\n\n")
        sbTrack.setValue(replaced, forKey: "lyrics")
    }
}
