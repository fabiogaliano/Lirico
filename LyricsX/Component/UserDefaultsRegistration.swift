import AppKit
import GenericID

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
        let isHant = isZh && (currentLang.contains("-Hant") || currentLang.contains("-HK"))

        let defaultsUrl = Bundle.main.url(forResource: "UserDefaults", withExtension: "plist")!
        if let dict = NSDictionary(contentsOf: defaultsUrl) as? [String: Any] {
            defaults.register(defaults: dict)
        }
        defaults.register(defaults: [
            .desktopLyricsColor: NSColor.white,
            .desktopLyricsProgressColor: NSColor.controlAccentColor,
            .desktopLyricsShadowColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.55),
            .desktopLyricsBackgroundColor: #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.85),
            .lyricsWindowTextColor: #colorLiteral(red: 0.6, green: 0.6, blue: 0.6, alpha: 1),
            .lyricsWindowHighlightColor: NSColor.controlAccentColor,
            .preferBilingualLyrics: isZh,
            .chineseConversionIndex: isHant ? 2 : 0,
            .desktopLyricsXPositionFactor: 0.5,
            .desktopLyricsYPositionFactor: 0.9,
            .lyricsExplicitRestorationEnabled: false,
            .lyricsExplicitLexiconEntries: explicitLexiconSeed,
        ])
    }
}
