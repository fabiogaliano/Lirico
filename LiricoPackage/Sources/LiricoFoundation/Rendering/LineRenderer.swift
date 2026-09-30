import Foundation

// MARK: - Explicit restoration closures

/// The evidence available to restore one rendered lyrics document at display time.
///
/// `supportingCandidates` are the other fetched candidates for the same song,
/// kept around by the search/session layer so masked spans can be repaired by
/// cross-candidate consensus without changing which lyrics are selected.
public struct ExplicitRestorationContext {
    public let supportingCandidates: [Lyrics]

    public init(supportingCandidates: [Lyrics]) {
        self.supportingCandidates = supportingCandidates
    }
}

/// A per-render-pass closure that restores a single main lyric line.
///
/// `isTimedLine` is true for karaoke (word-timed) lines, where the displayed
/// glyph count must not change; the resolver maps that onto length-preserving
/// restoration in the pure engine.
public typealias ExplicitLineRestoration = (_ text: String, _ isTimedLine: Bool) -> String

/// The display-time restoration closures for one render pass.
///
/// Main lines may use cross-candidate consensus. Translation lines must stay
/// lexicon-only because the supporting candidates are alternate main-lyrics
/// documents, not aligned translation evidence.
public struct ExplicitRenderRestoration {
    public let mainLine: ExplicitLineRestoration
    public let translation: (_ text: String) -> String

    public init(mainLine: @escaping ExplicitLineRestoration, translation: @escaping (_ text: String) -> String) {
        self.mainLine = mainLine
        self.translation = translation
    }

    public static var identity: ExplicitRenderRestoration {
        ExplicitRenderRestoration(mainLine: { text, _ in text }, translation: { $0 })
    }
}

// MARK: - LineRenderer

/// Converts a raw lyrics line (and optional translation) into the final strings
/// that should appear on screen, applying Chinese character-set conversion via the
/// supplied converter (the app passes OpenCC's `ChineseConverter.convert`).
///
/// Each call site specifies which parts it wants converted — main line and/or translation —
/// via the `convert` option set. This makes asymmetric rendering decisions explicit rather
/// than scattered guard-blocks throughout display controllers.
public enum LineRenderer {

    // MARK: - Options

    /// Which parts of the line should be passed through the converter.
    public struct ConvertOptions: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// Apply conversion to the main lyric line when the lyrics language is Chinese.
        public static let mainLine    = ConvertOptions(rawValue: 1 << 0)
        /// Apply conversion to the translation attachment when its language is Chinese.
        public static let translation = ConvertOptions(rawValue: 1 << 1)
        /// Convert both main line and translation (most common case).
        public static let all: ConvertOptions = [.mainLine, .translation]
    }

    // MARK: - Render

    /// Return the display strings for a single line.
    ///
    /// - Parameters:
    ///   - line: The `LyricsLine` to render.
    ///   - lyricsLanguage: The dominant language of the lyrics (from `Lyrics.metadata.language`).
    ///   - translationLanguageCode: The language tag for the translation attachment, if any.
    ///   - convert: Which parts are eligible for Chinese conversion (default: `.all`).
    ///   - converter: Chinese character-set conversion, or nil when it's off.
    ///   - restoreExplicit: Optional display-time restoration plan for masked
    ///     explicit words. Display surfaces pass one; the Apple Music export path
    ///     omits it so the canonical exported text is never altered. Applied to
    ///     raw text *before* Chinese conversion so restoration sees the source glyphs.
    /// - Returns:
    ///   `(content, translation)` — the final display string for the main line and, when a
    ///   translation attachment exists under `translationLanguageCode`, the converted translation.
    ///   `translation` is `nil` when no attachment is found.
    public static func render(
        line: LyricsLine,
        lyricsLanguage: String?,
        translationLanguageCode: String?,
        convert: ConvertOptions = .all,
        converter: ((String) -> String)?,
        restoreExplicit: ExplicitRenderRestoration? = nil
    ) -> (content: String, translation: String?) {
        var content = line.content
        var translation = translationLanguageCode.flatMap { line.attachments[.translation(languageCode: $0)] }

        if let restoreExplicit {
            // Karaoke lines carry inline time-tag indices that are glyph offsets
            // into this string, so timed lines only get length-preserving repair.
            let isTimedLine = line.attachments.timetag != nil
            content = restoreExplicit.mainLine(content, isTimedLine)
            if let trans = translation {
                translation = restoreExplicit.translation(trans)
            }
        }

        if let converter {
            if convert.contains(.mainLine), lyricsLanguage?.hasPrefix("zh") == true {
                content = converter(content)
            }
            if convert.contains(.translation), translationLanguageCode?.hasPrefix("zh") == true,
               let trans = translation {
                translation = converter(trans)
            }
        }

        return (content, translation)
    }
}
