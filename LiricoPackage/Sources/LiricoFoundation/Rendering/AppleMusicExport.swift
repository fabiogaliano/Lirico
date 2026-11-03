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
            content = legacyDescription(of: lyrics, includeTranslation: includeTranslation, converter: converter)
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

    /// `Lyrics.legacyDescription`, with the choice of leaving out the 【translation】 it always
    /// appends. Each part is converted on its own, because a Chinese translation can sit beside
    /// Japanese lyrics whose kanji must stay as they are.
    private static func legacyDescription(of lyrics: Lyrics, includeTranslation: Bool, converter: ((String) -> String)?) -> String {
        let lyricsAreChinese = lyrics.metadata.language?.hasPrefix("zh") == true
        let translationCode = lyrics.metadata.translationLanguages.first
        let translationIsChinese = translationCode?.hasPrefix("zh") ?? lyricsAreChinese
        let convertLyrics = lyricsAreChinese ? converter : nil
        let convertTranslation = translationIsChinese ? converter : nil

        let tags = lyrics.idTags.map { "[\($0.key.rawValue):\(convertLyrics?($0.value) ?? $0.value)]" }
        let lines = lyrics.lines.map { line -> String in
            let content = convertLyrics?(line.content) ?? line.content
            guard includeTranslation, let translation = line.attachments.translation() else {
                return "[\(line.timeTag)]\(content)"
            }
            return "[\(line.timeTag)]\(content)【\(convertTranslation?(translation) ?? translation)】"
        }
        return (tags + lines).joined(separator: "\n")
    }
}
