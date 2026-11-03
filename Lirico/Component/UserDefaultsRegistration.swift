import AppKit
import GenericID
import LiricoFoundation

enum UserDefaultsRegistration {
    /// Starter set of uncensored words for explicit-word restoration.
    ///
    /// Grounded in the most-censored forms actually found in saved lyrics plus
    /// published profanity-frequency analysis. Variants (plurals, -ing/-in/-ed,
    /// motherf*) are listed explicitly because the matcher restores per word
    /// length — "fuck" alone cannot recover "f**king" or "f**ked". Users extend
    /// this in Filter preferences.
    /// "slut" is intentionally excluded: it collides with "shit" under the very
    /// common "s**t" mask and would make that token ambiguous (left censored).
    /// "nigger" is disambiguated from "niggas" by the trailing letter
    /// (n****r vs n****s); the deep all-mask form n***** is blocked by the
    /// matcher's confidence gate either way.
    static let explicitLexiconSeed: [String] = [
        "shit", "fuck", "fucking", "fuckin", "fucked",
        "bitch", "bitches",
        "asshole", "ass",
        "nigga", "niggas", "nigger",
        "dick", "cock", "pussy", "cunt", "prick", "tits",
        "damn", "goddamn",
        "hoe", "hoes", "whore", "faggot",
        "motherfucker", "motherfuckers", "motherfucking",
        "weed",
    ]

    static func register(defaults: UserDefaults = .standard) {
        ArchivedColorBindingTransformer.register()
        let currentLang = NSLocale.preferredLanguages.first ?? "en"
        let isZh = currentLang.hasPrefix("zh") || currentLang.hasPrefix("yue")

        migrateJapaneseReading(defaults: defaults)

        let defaultsUrl = Bundle.main.url(forResource: "UserDefaults", withExtension: "plist")!
        if let dict = NSDictionary(contentsOf: defaultsUrl) as? [String: Any] {
            defaults.register(defaults: dict)
        }
        defaults.register(defaults: [
            .desktopLyricsColor: NSColor.white,
            .desktopLyricsProgressColor: NSColor.controlAccentColor,
            .desktopLyricsShadowColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.55),
            .desktopLyricsBackgroundColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.85),
            // The lyrics window and Sync by Ear are always dark panels.
            .lyricsWindowTextColor: NSColor.white,
            .lyricsWindowHighlightColor: NSColor.controlAccentColor,
            .lyricsWindowKeepsOnTop: true,
            .preferBilingualLyrics: isZh,
            .chineseConversionIndex: ChineseConversion.defaultValue(forLanguage: currentLang),
            .lyricsKoreanReading: LyricsReading.Korean.original.rawValue,
            .lyricsJapaneseReading: LyricsReading.Japanese.original.rawValue,
            .desktopLyricsXPositionFactor: 0.5,
            .desktopLyricsYPositionFactor: 0.9,
            .lyricsExplicitRestorationEnabled: false,
            .lyricsExplicitLexiconEntries: explicitLexiconSeed,
        ])
    }

    /// Furigana and romaji were two switches before Japanese got a single choice.
    private static func migrateJapaneseReading(defaults: UserDefaults) {
        let oldFurigana = "DesktopLyricsEnableFurigana"
        let oldRomaji = "DesktopLyricsEnableRomajin"
        guard defaults.object(forKey: oldFurigana) != nil || defaults.object(forKey: oldRomaji) != nil else { return }
        defaults[.lyricsJapaneseReading] = LyricsReading.Japanese.migrated(
            furigana: defaults.bool(forKey: oldFurigana),
            romaji: defaults.bool(forKey: oldRomaji)
        ).rawValue
        defaults.removeObject(forKey: oldFurigana)
        defaults.removeObject(forKey: oldRomaji)
    }
}
