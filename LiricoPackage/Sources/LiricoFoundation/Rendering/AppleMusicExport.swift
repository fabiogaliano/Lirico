import Foundation

/// The text Lirico writes into an Apple Music track's lyrics field.
public enum AppleMusicExport {
    /// Plain LRC is LiricoKit's legacy format: one line per timestamp, with the translation
    /// inline in 【】 when `includeTranslation`. Otherwise lines are plain text, each followed
    /// by its translation when `includeTranslation`. Restoration is never applied, so the
    /// export stays canonical.
    public static func text(
        for lyrics: Lyrics,
        plainLRC: Bool,
        includeTranslation: Bool,
        converter: ((String) -> String)?
    ) -> String {
        let content: String
        if plainLRC {
            var legacy = includeTranslation ? lyrics.legacyDescription : untranslatedLegacyDescription(of: lyrics)
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

    /// `Lyrics.legacyDescription` without the 【translation】 it always appends.
    private static func untranslatedLegacyDescription(of lyrics: Lyrics) -> String {
        let tags = lyrics.idTags.map { "[\($0.key.rawValue):\($0.value)]" }
        let lines = lyrics.lines.map { "[\($0.timeTag)]\($0.content)" }
        return (tags + lines).joined(separator: "\n")
    }
}
