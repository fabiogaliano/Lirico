import Foundation

/// How the user wants to read lyrics in each language. Display only: exports never use it.
public struct LyricsReading: Equatable, Sendable {
    /// Raw values are stored in user defaults.
    public enum Korean: Int, Sendable {
        case original = 0
        case romanized = 1
        /// Hangul with small romanization under it, which only desktop lyrics can draw.
        case annotated = 2
    }

    /// Raw values are stored in user defaults.
    public enum Japanese: Int, Sendable {
        case original = 0
        case furigana = 1
        case romanized = 2

        /// Romaji used to be drawn only when furigana was also on, so someone with romaji on
        /// wanted it either way and gets it now.
        public static func migrated(furigana: Bool, romaji: Bool) -> Japanese {
            if romaji { return .romanized }
            return furigana ? .furigana : .original
        }
    }

    public var korean: Korean
    public var japanese: Japanese
    public var chinesePinyin: Bool

    public init(korean: Korean = .original, japanese: Japanese = .original, chinesePinyin: Bool = false) {
        self.korean = korean
        self.japanese = japanese
        self.chinesePinyin = chinesePinyin
    }

    public static let original = LyricsReading()

    /// For vertical desktop lyrics, where small text under Hangul can't be drawn.
    public var withoutAnnotations: LyricsReading {
        var reading = self
        if reading.korean == .annotated { reading.korean = .romanized }
        return reading
    }
}

/// The values stored for the Chinese picker.
public enum ChineseConversion {
    public static let none = 0
    public static let simplified = 1
    public static let traditional = 2
    public static let traditionalTaiwan = 3
    public static let traditionalHongKong = 4
    public static let pinyin = 5

    /// `language` is a BCP 47 tag such as `zh-Hant-TW`.
    public static func defaultValue(forLanguage language: String) -> Int {
        guard language.hasPrefix("zh") || language.hasPrefix("yue") else { return none }
        if language.contains("-HK") || language.contains("-MO") { return traditionalHongKong }
        if language.contains("-TW") { return traditionalTaiwan }
        return language.contains("-Hant") ? traditional : none
    }
}
