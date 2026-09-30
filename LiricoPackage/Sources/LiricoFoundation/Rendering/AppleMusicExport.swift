import Foundation

/// The text Lirico writes into an Apple Music track's lyrics field.
public enum AppleMusicExport {
    /// Plain LRC is LyricsKit's legacy format: one line per timestamp, with any translation
    /// inline in 【】 whatever `includeTranslation` says. Otherwise lines are plain text, each
    /// followed by its translation when `includeTranslation`. Restoration is never applied,
    /// so the export stays canonical.
    public static func text(
        for lyrics: Lyrics,
        plainLRC: Bool,
        includeTranslation: Bool,
        converter: ((String) -> String)?
    ) -> String {
        let content: String
        if plainLRC {
            var legacy = lyrics.legacyDescription
            if let converter, lyrics.metadata.language?.hasPrefix("zh") == true {
                legacy = converter(legacy)
            }
            content = legacy
        } else {
            let translationCode = includeTranslation ? lyrics.metadata.translationLanguages.first : nil
            content = lyrics.lines.map { line -> String in
                let (main, translation) = LineRenderer.render(
                    line: line,
                    lyricsLanguage: lyrics.metadata.language,
                    translationLanguageCode: translationCode,
                    converter: converter
                )
                if let translation {
                    return main + "\n" + translation
                }
                return main
            }.joined(separator: "\n")
        }
        return content.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    }
}
