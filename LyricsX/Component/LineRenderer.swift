import LyricsXFoundation
import OpenCC

/// Converts a raw lyrics line (and optional translation) into the final strings
/// that should appear on screen, applying Chinese character-set conversion according
/// to the user's `chineseConversionIndex` preference.
///
/// Each call site specifies which parts it wants converted — main line and/or translation —
/// via the `convert` option set. This makes asymmetric rendering decisions explicit rather
/// than scattered guard-blocks throughout display controllers.
///
/// Usage:
/// ```swift
/// let (main, trans) = LineRenderer.render(
///     line: lrc,
///     lyricsLanguage: lyrics.metadata.language,
///     translationLanguageCode: lyrics.metadata.translationLanguages.first,
///     convert: [.mainLine, .translation]
/// )
/// ```
enum LineRenderer {

    // MARK: - Options

    /// Which parts of the line should be passed through `ChineseConverter`.
    struct ConvertOptions: OptionSet {
        let rawValue: Int
        /// Apply conversion to the main lyric line when the lyrics language is Chinese.
        static let mainLine    = ConvertOptions(rawValue: 1 << 0)
        /// Apply conversion to the translation attachment when its language is Chinese.
        static let translation = ConvertOptions(rawValue: 1 << 1)
        /// Convert both main line and translation (most common case).
        static let all: ConvertOptions = [.mainLine, .translation]
    }

    // MARK: - Render

    /// Return the display strings for a single line.
    ///
    /// - Parameters:
    ///   - line: The `LyricsLine` to render.
    ///   - lyricsLanguage: The dominant language of the lyrics (from `Lyrics.metadata.language`).
    ///   - translationLanguageCode: The language tag for the translation attachment, if any.
    ///   - convert: Which parts are eligible for Chinese conversion (default: `.all`).
    /// - Returns:
    ///   `(content, translation)` — the final display string for the main line and, when a
    ///   translation attachment exists under `translationLanguageCode`, the converted translation.
    ///   `translation` is `nil` when no attachment is found.
    static func render(
        line: LyricsLine,
        lyricsLanguage: String?,
        translationLanguageCode: String?,
        convert: ConvertOptions = .all
    ) -> (content: String, translation: String?) {
        var content = line.content
        var translation = translationLanguageCode.flatMap { line.attachments[.translation(languageCode: $0)] }

        if let converter = ChineseConverter.shared {
            if convert.contains(.mainLine), lyricsLanguage?.hasPrefix("zh") == true {
                content = converter.convert(content)
            }
            if convert.contains(.translation), translationLanguageCode?.hasPrefix("zh") == true,
               let trans = translation {
                translation = converter.convert(trans)
            }
        }

        return (content, translation)
    }
}
