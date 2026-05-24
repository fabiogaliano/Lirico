import AppKit
import GenericID

enum UserDefaultsRegistration {
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
        ])
    }
}
