import Foundation
import LyricsXFoundation
import MusicPlayer
import OpenCC
import Regex

/// Writes lyrics into the currently playing Apple Music track via its scripting bridge.
///
/// Pulled out of the lyrics-management hub so that the session type owns
/// state, not Apple-Music-specific formatting + scripting glue. Mirrors the
/// pattern used by `LyricsPreparer` / `LocalLyricsLoader`: a small `enum`
/// namespace of pure static functions.
enum LyricsPersister {
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
