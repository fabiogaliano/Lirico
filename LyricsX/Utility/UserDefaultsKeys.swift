import AppKit
import GenericID

let defaults = UserDefaults.standard
let groupDefaults = UserDefaults(suiteName: lyricsXGroupIdentifier)!

extension UserDefaults.DefaultsKeys {
    static let notifiedUpdateVersion = Key<String?>("NotifiedUpdateVersion")
    static let noSearchingTrackIds = Key<[String]>("NoSearchingTrackIds")
    static let noSearchingAlbumNames = Key<[String]>("NoSearchingAlbumNames")

    // Menu
    static let desktopLyricsEnabled = Key<Bool>("DesktopLyricsEnabled")
    static let menuBarLyricsEnabled = Key<Bool>("MenuBarLyricsEnabled")
    static let touchBarLyricsEnabled = Key<Bool>("TouchBarLyricsEnabled")

    // General
    static let preferredPlayerIndex = Key<Int>("PreferredPlayerIndex")
    static let launchAndQuitWithPlayer = Key<Bool>("LaunchAndQuitWithPlayer")

    static let lyricsSavingPathPopUpIndex = Key<Int>("LyricsSavingPathPopUpIndex")
    static let lyricsCustomSavingPathBookmark = Key<Data?>("LyricsCustomSavingPathBookmark")
    static let loadLyricsBesideTrack = Key<Bool>("LoadLyricsBesideTrack")

    static let selectedLanguage = Key<String?>("SelectedLanguage")

    static let preferBilingualLyrics = Key<Bool>("PreferBilingualLyrics")
    static let chineseConversionIndex = Key<Int>("ChineseConversionIndex")

    static let combinedMenubarLyrics = Key<Bool>("CombinedMenubarLyrics")

    static let hideLyricsWhenMousePassingBy = Key<Bool>("HideLyricsWhenMousePassingBy")
    static let disableLyricsWhenPaused = Key<Bool>("DisableLyricsWhenPaused")
    static let disableLyricsWhenSreenShot = Key<Bool>("DisableLyricsWhenSreenShot")

    static let hideMenuBarItems = Key<Bool>("HideMenuBarItems")

    // Display
    static let desktopLyricsOneLineMode = Key<Bool>("DesktopLyricsOneLineMode")
    static let desktopLyricsVerticalMode = Key<Bool>("DesktopLyricsVerticalMode")
    static let desktopLyricsDraggable = Key<Bool>("DesktopLyricsDraggable")

    static let desktopLyricsXPositionFactor = Key<CGFloat>("DesktopLyricsXPositionFactor")
    static let desktopLyricsYPositionFactor = Key<CGFloat>("DesktopLyricsYPositionFactor")

    static let desktopLyricsEnableFurigana = Key<Bool>("DesktopLyricsEnableFurigana")
    static let desktopLyricsEnableRomajin = Key<Bool>("DesktopLyricsEnableRomajin")

    static let desktopLyricsFontName = Key<String>("DesktopLyricsFontName")
    static let desktopLyricsFontSize = Key<Int>("DesktopLyricsFontSize")
    static let desktopLyricsFontNameFallback = Key<[String]>("DesktopLyricsFontNameFallback")

    static let desktopLyricsColor = Key<NSColor>("DesktopLyricsColor", transformer: .keyedArchive)
    static let desktopLyricsProgressColor = Key<NSColor>("DesktopLyricsProgressColor", transformer: .keyedArchive)
    static let desktopLyricsShadowColor = Key<NSColor>("DesktopLyricsShadowColor", transformer: .keyedArchive)
    static let desktopLyricsBackgroundColor = Key<NSColor>("DesktopLyricsBackgroundColor", transformer: .keyedArchive)

    static let lyricsWindowFontName = Key<String>("LyricsWindowFontName")
    static let lyricsWindowFontSize = Key<Int>("LyricsWindowFontSize")
    static let lyricsWindowFontNameFallback = Key<[String]>("LyricsWindowFontNameFallback")

    static let lyricsWindowTextColor = Key<NSColor>("LyricsWindowTextColor", transformer: .keyedArchive)
    static let lyricsWindowHighlightColor = Key<NSColor>("LyricsWindowHighlightColor", transformer: .keyedArchive)

    // Shortcut
    static let shortcutToggleMenuBarLyrics = Key<String>("ShortcutToggleMenuBarLyrics")
    static let shortcutToggleKaraokeLyrics = Key<String>("ShortcutToggleKaraokeLyrics")
    static let shortcutShowLyricsWindow = Key<String>("ShortcutShowLyricsWindow")
    static let shortcutOffsetIncrease = Key<String>("ShortcutOffsetIncrease")
    static let shortcutOffsetDecrease = Key<String>("ShortcutOffsetDecrease")
    static let shortcutWriteToiTunes = Key<String>("ShortcutWriteToiTunes")
    static let shortcutSearchLyrics = Key<String>("ShortcutSearchLyrics")
    static let shortcutWrongLyrics = Key<String>("ShortcutWrongLyrics")
    static let shortcutTogglePreferences = Key<String>("ShortcutTogglePreferences")

    // Filter
    static let lyricsFilterEnabled = Key<Bool>("LyricsFilterEnabled")
    static let lyricsSmartFilterEnabled = Key<Bool>("LyricsSmartFilterEnabled")
    static let lyricsFilterKeys = Key<[String]>("LyricsFilterKeys")

    // Lab
    static let useSystemWideNowPlaying = Key<Bool>("UseSystemWideNowPlaying")
    static let systemWideNowPlayingAppList = Key<[String]>("SystemWideNowPlayingAppList")

    static let writeiTunesWithTranslation = Key<Bool>("WriteiTunesWithTranslation")
    static let writeToiTunesAutomatically = Key<Bool>("WriteToiTunesAutomatically")
    static let writeiTunesConvertToPlainLRC = Key<Bool>("WriteiTunesConvertToPlainLRC")

    static let globalLyricsOffset = Key<Int>("GlobalLyricsOffset")

    static let musixmatchToken = Key<String?>("MusixmatchToken")

    //
    static let isInMASReview = Key<Bool?>("isInMASReview")

    static let launchHelperTime = Key<Date?>("launchHelperTime")

    static let appleLanguages = Key<[String]>("AppleLanguages")

    static let isShowLyricsHUD = Key<Bool>("isShowLyricsHUD")

    // Source Priority
    static let lyricsSourcePriorityEnabled = Key<Bool>("LyricsSourcePriorityEnabled")
    static let lyricsSourcePriorityOrder = Key<[String]>("LyricsSourcePriorityOrder")
}

extension CGFloat: @retroactive DefaultConstructible {}
