# Preferences SwiftUI Migration

## Current status

- Current phase: Phase 7 — Cleanup/storyboard retirement complete
- Last completed phase: Phase 7
- Build status: BUILD SUCCEEDED (Debug, 2026-05-23)
- Migration: COMPLETE — all storyboard dependencies removed, all 6 panes live in SwiftUI
- Known blockers: None

## Phase checklist

- [x] Phase 0 — Audit and migration plan
- [ ] Phase 0 review
- [x] Phase 1 — SwiftUI shell + Lab tracer bullet
- [x] Phase 1 review
- [x] Phase 2 — Shortcut pane
- [x] Phase 2 review
- [x] Phase 3 — Filter pane
- [x] Phase 3 review
- [x] Phase 4 — General pane
- [x] Phase 4 review
- [x] Phase 5 — Display pane
- [x] Phase 5 review
- [x] Phase 6 — Source pane
- [x] Phase 6 review
- [x] Phase 7 — Cleanup/storyboard retirement
- [x] Phase 7 review

## Pane migration map

### General pane (`PreferenceGeneralViewController`)

**Storyboard source**: `Preferences.storyboard` scene for `PreferenceGeneralViewController`
**Settings/defaults touched**:
- `PlayerSettings.preferredPlayerIndex` (Int, tag-based: -1=auto, 0=Apple Music, 1=Spotify, 2=Vox, 3=Audirvana, 4=Swinsian)
- `PlayerSettings.launchAndQuitWithPlayer` (Bool, Cocoa Binding to `values.LaunchAndQuitWithPlayer`)
- `PersistenceSettings.customSavingDirectory` (URL? via security-scoped bookmark)
- `PersistenceSettings.shouldLoadLyricsBesideTrack` (Bool, Cocoa Binding to `values.LoadLyricsBesideTrack`)
- `defaults[.lyricsSavingPathPopUpIndex]` (Int, Cocoa Binding to `values.LyricsSavingPathPopUpIndex`)
- `defaults[.globalLyricsOffset]` (Int, Cocoa Binding to `values.GlobalLyricsOffset`)
- `defaults[.strictSearchEnabled]` (Bool, Cocoa Binding)
- `defaults[.preferBilingualLyrics]` (Bool, Cocoa Binding)
- `defaults[.chineseConversionIndex]` (Int, popup selectedIndex binding)
- `defaults[.combinedMenubarLyrics]` (Bool, Cocoa Binding)
- `defaults[.selectedLanguage]` (String?, manual code)
- `defaults[.appleLanguages]` (String array, manual code)
- `defaults[.hideMenuBarItems]` (Bool, Cocoa Binding)
- `LaunchAtLogin.kvo` (Bool, KVO binding)

**Actions/workflows**:
- `toggleAutoLaunchAction` — `SMLoginItemSetEnabled`
- `showInFinderAction` — opens storage directory in Finder
- `chooseSavingPathAction` — `NSOpenPanel` sheet for custom saving directory
- `chooseLanguageAction` — language popup selection
- `helpTranslateAction` — opens Crowdin URL
- `preferredPlayerAction` — sets preferred player, disables autolaunch for "auto", disables beside-track for players that don't support it

**Native SwiftUI**: Toggle, Picker (for player, language, saving path, Chinese conversion), TextField (offset), Link (Crowdin)
**AppKit bridges needed**: None expected — all controls have SwiftUI equivalents
**Notes**: Language selection has special index math (index 0 = system, gap at index 1, localizations start at index 2). Player-specific conditional enabling of "beside track" and "launch with player" must be preserved.

### Display pane (`PreferenceDisplayViewController`)

**Storyboard source**: `Preferences.storyboard` scene for `PreferenceDisplayViewController`
**Settings/defaults touched**:
- `defaults[.desktopLyricsOneLineMode]` (Bool)
- `defaults[.desktopLyricsVerticalMode]` (Bool)
- `defaults[.desktopLyricsDraggable]` (Bool)
- `defaults[.desktopLyricsFontName]` (String)
- `defaults[.desktopLyricsFontSize]` (Int)
- `defaults[.desktopLyricsFontNameFallback]` ([String])
- `defaults[.desktopLyricsColor]` (NSColor, keyed archive)
- `defaults[.desktopLyricsProgressColor]` (NSColor, keyed archive)
- `defaults[.desktopLyricsShadowColor]` (NSColor, keyed archive)
- `defaults[.desktopLyricsBackgroundColor]` (NSColor, keyed archive)
- `defaults[.lyricsWindowFontName]` (String)
- `defaults[.lyricsWindowFontSize]` (Int)
- `defaults[.lyricsWindowTextColor]` (NSColor, keyed archive)
- `defaults[.lyricsWindowHighlightColor]` (NSColor, keyed archive)
- `defaults[.disableLyricsWhenPaused]` (Bool)
- `defaults[.disableLyricsWhenSreenShot]` (Bool)
- `defaults[.hideLyricsWhenMousePassingBy]` (Bool)

**Actions/workflows**:
- `fontChanged(from:to:sender:)` — updates font name/size, manages font fallback list
- `removeFontFallbackAction` — clears fallback list
- Font picker via `FontSelectTextField` (custom NSTextField subclass using NSFontManager/NSFontPanel)

**Native SwiftUI**: Toggle, Picker
**AppKit bridges needed**:
- `FontSelectTextField` → `NSViewRepresentable` wrapper (uses NSFontManager/NSFontPanel with swizzling)
- Color controls: Try `ColorPicker(supportsOpacity: true)` first. Colors stored as `NSColor` via keyed archive transformer (`Key<NSColor>("...", transformer: .keyedArchive)`). Need to verify `Color ↔ NSColor` round-trip preserves alpha and archive format. If not, bridge `AlphaColorWell`.

### Shortcut pane (`PreferenceShortcutViewController`)

**Storyboard source**: `Preferences.storyboard` — grid of 9 `MASShortcutView` instances
**Settings/defaults touched**: All via `associatedUserDefaultsKey` runtime attribute:
- `ShortcutToggleMenuBarLyrics`
- `ShortcutToggleKaraokeLyrics`
- `ShortcutShowLyricsWindow`
- `ShortcutOffsetIncrease`
- `ShortcutOffsetDecrease`
- `ShortcutWriteToiTunes`
- `ShortcutSearchLyrics` (has `isRemovedDuringMASReview` flag)
- `ShortcutWrongLyrics`
- `ShortcutTogglePreferences`

**Actions/workflows**: Controller is empty — all behavior is in `MASShortcutView` and `MASShortcutBinder`.
**Native SwiftUI**: Labels only
**AppKit bridges needed**: `MASShortcutView` must be wrapped in `NSViewRepresentable`. Each shortcut view needs its `associatedUserDefaultsKey` set.

### Filter pane (`PreferenceFilterViewController`)

**Storyboard source**: `Preferences.storyboard` — NSArrayController-driven table with add/remove/reset
**Settings/defaults touched**:
- `defaults[.lyricsFilterEnabled]` (Bool, Cocoa Binding)
- `defaults[.lyricsSmartFilterEnabled]` (Bool, Cocoa Binding — appears in storyboard)
- `defaults[.lyricsFilterKeys]` ([String], loaded/saved via `loadFilter()`/`saveFilter()`)

**Actions/workflows**:
- `loadFilter()` — reads `lyricsFilterKeys` from defaults, converts to `[LyricsFilterKeyword]`
- `saveFilter()` — writes keywords back to defaults as `[String]`
- `resetFilterKey` — removes defaults key, reloads (restores plist defaults)
- Storyboard uses `NSArrayController` bound to `directFilter` with `arrangedObjects.keyword` column binding

**Native SwiftUI**: Toggle, List with editable text fields, add/remove/reset buttons
**AppKit bridges needed**: None — `LyricsFilterKeyword` NSCoding class only needed for storyboard bindings; SwiftUI version can work directly with `[String]`

### Lab pane (`PreferenceLabViewController`)

**Storyboard source**: `Preferences.storyboard` — grid layout
**Settings/defaults touched**:
- `defaults[.touchBarLyricsEnabled]` (Bool, programmatic Cocoa Binding via `bind(\.value, withDefaultName:)`)
- `SearchSettings.musixmatchToken` (String?, via `searchSettings`)
- `defaults[.useSystemWideNowPlaying]` (Bool, Cocoa Binding)
- `defaults[.desktopLyricsEnableFurigana]` (Bool, Cocoa Binding)
- `defaults[.desktopLyricsEnableRomajin]` (Bool, Cocoa Binding)
- `defaults[.writeiTunesWithTranslation]` (Bool, Cocoa Binding)
- `defaults[.writeToiTunesAutomatically]` (Bool, Cocoa Binding)
- `defaults[.writeiTunesConvertToPlainLRC]` (Bool, Cocoa Binding)
- Touch Bar customization enable button (Cocoa Binding enabled to `TouchBarLyricsEnabled`)
- Now Playing application list (via `PlayerSettings.systemWideNowPlayingAppList`)

**Actions/workflows**:
- `musixmatchTokenChanged` — trims whitespace, collapses empty to nil, writes to `SearchSettings`
- `customizeAllowsNowPlayingApplicationsAction` — presents `NowPlayingApplicationListViewController` as sheet
- `customizeTouchBarAction` — `NSApplication.shared.toggleTouchBarCustomizationPalette`

**Native SwiftUI**: Toggle, TextField, Button
**AppKit bridges needed**: 
- `NowPlayingApplicationListViewController` → present as sheet via `NSViewControllerRepresentable` or keep using `presentAsSheet` from hosting controller
- Touch Bar customization palette button → call `NSApplication.shared.toggleTouchBarCustomizationPalette` from button action

### Source pane (`PreferenceSourceViewController`)

**Storyboard source**: `Preferences.storyboard` — enable checkbox + NSTableView with drag-drop
**Settings/defaults touched**:
- `SearchSettings.sourcePriorityEnabled` (Bool)
- `SearchSettings.sourcePriorityOrder` ([String])
- `LyricsSelector.shared.normalize(against:settings:)` on load and after reorder

**Actions/workflows**:
- `toggleSourcePriority` — enables/disables priority ordering, dims table
- Drag-and-drop table reordering via `NSTableViewDataSource` drag methods
- `savePriorityOrder` — writes order to SearchSettings, re-normalizes

**Native SwiftUI**: Toggle, List with `onMove` (macOS 11+ — `List` + `ForEach` with `.onMove`)
**AppKit bridges needed**: None expected — SwiftUI `List` with `ForEach.onMove` should handle reordering. If drag-drop fidelity is a concern, bridge the NSTableView.

## Decisions

### Phase 0 — D1: Window controller approach

**Decision**: Replace storyboard-based `PreferenceWindowController` with programmatic `NSWindow` + `NSHostingController` wrapping a `PreferencesView` with `TabView(selection:)`.
**Alternatives**: (a) Keep storyboard shell and inject `NSHostingController` per tab; (b) Use SwiftUI `Settings` scene (requires SwiftUI App lifecycle).
**Rationale**: Option (a) adds complexity of maintaining storyboard alongside SwiftUI. Option (b) requires abandoning AppKit lifecycle. Programmatic window creation via `PreferenceWindowController` is the cleanest — keeps `.create()` working via a new `convenience init`, preserves `AppContainer.preferencesWindowController`.
**Risk**: Must ensure window size/position/toolbar behavior matches. Low risk — `NSTabViewController` with `tabStyle = .toolbar` is straightforward to reproduce.
**Deferred**: Consider `Settings` scene if app migrates to SwiftUI lifecycle in future.

### Phase 0 — D2: Color controls

**Decision**: Start with `ColorPicker(supportsOpacity: true)` for color controls. Colors are stored as `NSColor` via keyed archive. `Color(nsColor:)` and `NSColor(color)` round-trip is reliable on macOS 11+. Will verify alpha persistence during Phase 5 implementation.
**Alternatives**: Bridge `AlphaColorWell` immediately.
**Rationale**: `ColorPicker` is simpler, native SwiftUI. If alpha or archive fidelity breaks, fallback to `AlphaColorWell` bridge is a small change.
**Risk**: Low — can be caught in Phase 5 review.

### Phase 0 — D3: Tab order

**Decision**: Keep existing tab order (General, Display, Shortcut, Filter, Lab, Source).
**Alternatives**: Reorder to group "what you see" (Display) next to "what you configure" (General).
**Rationale**: Preserving existing order minimizes user confusion. No strong UX reason to reorder.

### Phase 0 — D4: Shortcut recorder approach

**Decision**: Bridge `MASShortcutView` via `NSViewRepresentable`. The shortcut recording logic is complex (key capture, conflict detection, `associatedUserDefaultsKey` binding) and all handled internally by `MASShortcutView`.
**Alternatives**: Build custom SwiftUI shortcut recorder.
**Rationale**: Building a custom recorder would be high-risk and out of scope. The bridge preserves exact behavior.

### Phase 0 — D5: `@AppStorage` vs view model

**Decision**: Use `@AppStorage` directly for simple Bool/Int/String defaults. Use a small `ObservableObject` view model only when the pane needs coordinated logic (e.g., General pane's player-conditional enabling, Display pane's font management). For NSColor defaults (keyed archive), use a view model with manual `UserDefaults` observation since `@AppStorage` doesn't support custom transformers.
**Alternatives**: View models for everything; `@AppStorage` for everything.
**Rationale**: `@AppStorage` is simplest for Bool toggles. View models add boilerplate for no benefit on simple panes. Colors need manual handling either way.

## Unknowns resolved autonomously

### `StoryboardWindowController` protocol location
**Unknown**: Where is `StoryboardWindowController` defined?
**Resolution**: Found in UIFoundation package (`UIFoundationAppKit/Controller/StoryboardWindowController.swift`). It requires a `storyboard` static property and provides a `create()` factory method. The new `PreferenceWindowController` will stop conforming to `StoryboardWindowController` once the storyboard is removed; instead it will use a programmatic window init.

### Shortcut pane controller is empty
**Unknown**: How are MASShortcutView instances connected?
**Resolution**: Each `MASShortcutView` in the storyboard has `associatedUserDefaultsKey` set via User Defined Runtime Attributes. The actual shortcut-to-action binding happens in `ShortcutBindings.install(actionTarget:binder:)` called from `AppDelegate`, not from the preference pane. The pane just provides the recording UI.

### Two Shortcut pane duplicates in storyboard
**Unknown**: Why are there ~18 `MASShortcutView` instances?
**Resolution**: The storyboard contains the Shortcut pane twice — once in a `gridView`-based layout (IDs starting at `atC-aF-Wgo`) and once in a constraint-based flat layout (IDs starting at `Wl2-0l-Mvk`). Both reference the same 9 shortcut keys. Only one is actually instantiated at runtime based on which scene is connected to the tab controller. This is likely a storyboard revision artifact.

### `LyricsFilterKeyword` `@objc(FilterKey)` name
**Unknown**: Is the ObjC name important?
**Resolution**: The `@objc(FilterKey)` annotation exists solely for Interface Builder bindings in `Preferences.storyboard`. Once the filter pane is SwiftUI and no longer uses `NSArrayController`, the SwiftUI version can work directly with `[String]` without needing `LyricsFilterKeyword` at all.

## Changed files by phase

### Phase 0
- Added: `docs/implementation/preferences-swiftui-migration.md` (this document)

### Phase 1
- Added: `LyricsX/Preferences/SettingsSection.swift` — reusable `SettingsSection<Content>` and `SettingsRow<Content>` SwiftUI views
- Added: `LyricsX/Preferences/LabPreferencesView.swift` — full SwiftUI Lab pane; bridges `NowPlayingApplicationListViewController` via `NSViewControllerRepresentable`
- Added: `LyricsX/Preferences/PreferencesView.swift` — root `TabView` with Lab pane live and 5 placeholder panes
- Modified: `LyricsX/Preferences/PreferenceWindowController.swift` — removed `StoryboardWindowController` / `UIFoundation` import; replaced with programmatic `NSWindow` + `NSHostingController`; kept `static func create()` factory
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference`, `PBXBuildFile`, Preferences group entry, and Sources build phase entry for all three new files

### Phase 2
- Added: `LyricsX/Preferences/ShortcutPreferencesView.swift` — private `ShortcutRecorderView: NSViewRepresentable` bridging `MASShortcutView`; `ShortcutPreferencesView` with 4 `SettingsSection` groups and 9 shortcut rows
- Modified: `LyricsX/Preferences/PreferencesView.swift` — replaced Shortcut tab placeholder with `ShortcutPreferencesView()`
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference` (`FA0000002F200000000A0004`), `PBXBuildFile` (`FA0000012F200000000A0004`), Preferences group entry, and Sources build phase entry for `ShortcutPreferencesView.swift`

### Phase 3
- Added: `LyricsX/Preferences/FilterPreferencesView.swift` — `FilterPreferencesView` with two `SettingsSection`s: Filter Settings (two `@AppStorage` toggles) and Filter Keywords (scrollable custom keyword list with add/remove/reset, regex indicator badge)
- Modified: `LyricsX/Preferences/PreferencesView.swift` — replaced Filter tab placeholder with `FilterPreferencesView()`
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference` (`FA0000002F200000000A0005`), `PBXBuildFile` (`FA0000012F200000000A0005`), Preferences group entry, and Sources build phase entry for `FilterPreferencesView.swift`

### Phase 4
- Added: `LyricsX/Preferences/GeneralPreferencesView.swift` — `GeneralPreferencesView` with four `SettingsSection`s: Music Player (radio-group picker + `LaunchAtLogin.Toggle`), Lyrics Files (saving path picker + Show in Finder + beside-track toggle), Search & Display (offset stepper, strict search, bilingual, Chinese conversion picker, combined menubar, hide menu bar), Language (locale picker + Crowdin link)
- Modified: `LyricsX/Preferences/PreferencesView.swift` — replaced General tab placeholder with `GeneralPreferencesView()`
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference` (`FA0000002F200000000A0006`), `PBXBuildFile` (`FA0000012F200000000A0006`), Preferences group entry, and Sources build phase entry for `GeneralPreferencesView.swift`

### Phase 5
- Added: `LyricsX/Preferences/DisplayPreferencesView.swift` — `DisplayPreferencesViewModel` (`ObservableObject`) managing NSColor↔SwiftUI Color round-trip and NSFont state; private `FontPickerCoordinator` (NSObject subclass handling NSFontManager/NSFontPanel lifecycle); private `FontPickerButton` (`NSViewRepresentable` wrapping an `NSButton` that opens `NSFontPanel`); `DisplayPreferencesView` with three `SettingsSection`s: Desktop Lyrics (font picker + fallback row + 4 ColorPickers + 3 toggles), Desktop Lyrics Behavior (3 toggles), HUD Lyrics Window (font picker + 2 ColorPickers)
- Modified: `LyricsX/Preferences/PreferencesView.swift` — replaced Display tab placeholder with `DisplayPreferencesView()`
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference` (`FA0000002F200000000A0007`), `PBXBuildFile` (`FA0000012F200000000A0007`), Preferences group entry, and Sources build phase entry for `DisplayPreferencesView.swift`

### Phase 6
- Added: `LyricsX/Preferences/SourcePreferencesView.swift` — `SourcePreferencesView` with one `SettingsSection`: toggle for `sourcePriorityEnabled`, description label, numbered source list (plain `List` with `ForEach` + `.onMove`), Move Up / Move Down buttons for macOS 11–12 compat. Loads via `onAppear` (normalize + load), saves on every mutation (toggle write-through to `SearchSettings`, `commitOrder()` after every move)
- Modified: `LyricsX/Preferences/PreferencesView.swift` — replaced Source tab placeholder with `SourcePreferencesView()`
- Modified: `LyricsX.xcodeproj/project.pbxproj` — added `PBXFileReference` (`FA0000002F200000000A0008`), `PBXBuildFile` (`FA0000012F200000000A0008`), Preferences group entry, and Sources build phase entry for `SourcePreferencesView.swift`

### Phase 7
**Files removed** (no remaining references outside storyboard):
- `LyricsX/Base.lproj/Preferences.storyboard` — main storyboard; `PreferenceWindowController` now creates a programmatic `NSWindow` + `NSHostingController`
- `LyricsX/mul.lproj/Preferences.xcstrings` — storyboard string catalog variant
- `LyricsX/Preferences/PreferenceViewController.swift` — base classes `PreferenceViewController` and `PreferenceTabViewController`
- `LyricsX/Preferences/PreferenceGeneralViewController.swift`
- `LyricsX/Preferences/PreferenceDisplayViewController.swift`
- `LyricsX/Preferences/PreferenceShortcutViewController.swift`
- `LyricsX/Preferences/PreferenceFilterViewController.swift`
- `LyricsX/Preferences/PreferenceLabViewController.swift`
- `LyricsX/Preferences/PreferenceSourceViewController.swift`
- `LyricsX/Preferences/AlphaColorWell.swift` — replaced by `ColorPicker(supportsOpacity: true)` in Phase 5
- `LyricsX/Preferences/FilterKey.swift` — `LyricsFilterKeyword` was only needed for storyboard `NSArrayController` bindings; `FilterPreferencesView` works directly with `[String]`
- `LyricsX/View/FontSelectTextField.swift` — replaced by `FontPickerCoordinator`/`FontPickerButton` in Phase 5; only referenced by `PreferenceDisplayViewController` and the storyboard

**Files kept**:
- `LyricsX/Preferences/PreferenceWindowController.swift` — still used by `AppContainer`; creates the preferences window programmatically
- `LyricsX/Preferences/NowPlayingApplicationListViewController.swift` — still used by `LabPreferencesView` via `NowPlayingApplicationListRepresentable`
- All SwiftUI preference pane files from Phases 1–6

**pbxproj changes**: Removed `PBXBuildFile`, `PBXFileReference`, group children, Sources build phase entries, Resources build phase entry, and `PBXVariantGroup` for all deleted files. `plutil -lint`: OK.

**Comment cleanup**:
- `LyricsX/Component/PersistenceSettings.swift` line 60: removed reference to `PreferenceGeneralViewController`
- `LyricsX/Component/LyricsSelector.swift` line 5: removed reference to `PreferenceSourceViewController`
- `LyricsX/Preferences/GeneralPreferencesView.swift` line 291: removed reference to `PreferenceGeneralViewController`

## Verification log

### Phase 0
- `git status --short`: Clean working tree (only `docs/prompt.md` staged — unrelated)
- No production code modified

### Phase 1
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep error:`: No errors
- Final result: `** BUILD SUCCEEDED **`
- Warnings: pre-existing storyboard `NSKeyedUnarchiveFromData` deprecation warnings (unrelated to Phase 1 changes); storyboard "unreachable" scenes warning (expected — storyboard is no longer the entry point)

### Phase 2
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep error:`: No errors
- Final result: `** BUILD SUCCEEDED **`

### Phase 3
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep -E "error:|BUILD"`: No errors
- Final result: `** BUILD SUCCEEDED **`

### Phase 4
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`: No errors
- Final result: `** BUILD SUCCEEDED **`

**Phase 4 review findings (2026-05-23)**

- Player tags: -1=auto, 0=Apple Music, 1=Spotify, 2=Vox, 3=Audirvana, 4=Swinsian — verified against `MusicPlayerName(index:)` in `Extension.swift`. Correct.
- `canLaunchWithPlayer` (nil-player → false): disabled when auto. Correct.
- `canLoadBesideTrack` (`supportsBesideTrackLyrics ?? true`): disabled for Spotify, Audirvana, Swinsian; enabled for Apple Music, Vox, and auto. Verified against `Extension.swift`. Correct.
- `LaunchAtLogin.Toggle` verified in `LaunchAtLogin-Legacy/Sources/LaunchAtLogin/Toggle.swift` — `init(_ title: some StringProtocol)` exists. Package ships `LaunchAtLogin.observable` via `Observable: ObservableObject`. Available on macOS 10.15+.
- Saving path popup: Default=tag 0, Custom=tag 1, conditional second item, Choose button opens NSOpenPanel. Correct per D3.
- Language picker: index 0 removes both keys, 2+ maps to `localizations[index-2]` via `applyLanguageSelection`. Verified against original `chooseLanguageAction`. Correct.
- Chinese conversion: 5 options (0=None, 1=Simplified, 2=Traditional, 3=Taiwan, 4=Hong Kong) — verified against `ChineseConverterProvider.rebuild(forIndex:)`. Correct.
- All `@AppStorage` keys verified against `UserDefaultsKeys.swift`: `PreferredPlayerIndex`, `LyricsSavingPathPopUpIndex`, `GlobalLyricsOffset`, `StrictSearchEnabled`, `PreferBilingualLyrics`, `ChineseConversionIndex`, `CombinedMenubarLyrics`, `HideMenuBarItems`, `LaunchAndQuitWithPlayer`, `LoadLyricsBesideTrack` — all match exactly.
- No side effects on other panes. `PreferencesView.swift` cleanly replaces General placeholder only.
- `plutil -lint`: OK.

**Bug found and fixed — `LaunchAtLogin.Toggle` semantic mismatch**:
- The original storyboard has TWO separate controls in the General pane: (1) `autoLaunchButton` titled "Auto launch & quit with music player", bound to `values.LaunchAndQuitWithPlayer` AND connected to `toggleAutoLaunchAction:` which calls `SMLoginItemSetEnabled(lyricsXHelperIdentifier, ...)` to register/unregister `LyricsXHelper` as a login item; (2) a separate "Launch at login" checkbox bound to `launchAtLogin.isEnabled` (controls the main app's system-level launch at login via `LaunchAtLogin.kvo`).
- The original `GeneralPreferencesView.swift` used a single `LaunchAtLogin.Toggle("Launch and quit with player")`, which controlled `LaunchAtLogin.observable.isEnabled` — a system login item using bundle ID `com.fabiogaliano.LyricsX-LaunchAtLoginHelper` (different from the actual `LyricsXHelper` bundle ID `com.fabiogaliano.LyricsXHelper`). The `@AppStorage("LaunchAndQuitWithPlayer")` binding was never written by that toggle.
- Fixed: replaced `LaunchAtLogin.Toggle` with `Toggle("Auto launch & quit with music player", isOn: $launchAndQuitWithPlayer)` + two `onChange` handlers: one calls `SMLoginItemSetEnabled(lyricsXHelperIdentifier, enabled)` when the toggle changes; one enforces the constraint (set to false, unregister helper) when the player switches to Auto. Added a second `LaunchAtLogin.Toggle("Launch at login")` to restore the system-level launch-at-login control.
- Build: no errors in `GeneralPreferencesView.swift` after fix. (`DisplayPreferencesView.swift` has pre-existing Phase 5 compile errors unrelated to Phase 4.)

### Phase 5
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`: No errors (one intermediate build failed due to Xcode IDE DB lock; retry succeeded)
- Final result: `** BUILD SUCCEEDED **`

**Phase 5 review findings (2026-05-23)**

- All 6 `@AppStorage` keys verified against `UserDefaultsKeys.swift`: `DesktopLyricsOneLineMode`, `DesktopLyricsVerticalMode`, `DesktopLyricsDraggable`, `HideLyricsWhenMousePassingBy`, `DisableLyricsWhenPaused`, `DisableLyricsWhenSreenShot` — all match exactly, including the `SreenShot` typo.
- All 6 view model color loads verified: `desktopLyricsColor`, `desktopLyricsProgressColor`, `desktopLyricsShadowColor`, `desktopLyricsBackgroundColor`, `lyricsWindowTextColor`, `lyricsWindowHighlightColor` — correct keys, correct fallback defaults.
- All 6 color save methods verified: each writes `NSColor(swiftUIColor)` back to the matching `Key<NSColor>(…, transformer: .keyedArchive)` key. Correct.
- Font fallback logic in `desktopFontChanged(from:to:)` verified line-by-line against original `PreferenceDisplayViewController.fontChanged(from:to:sender:)`. Logic is identical. One intentional addition: `desktopFont = newFont` on line 93 updates the published font property for UI refresh; this is correct.
- `fontFallback` reload (line 94) runs unconditionally after the `if` block in the new code vs only inside the block in the original. Harmless — the fallback array is unchanged when the condition is false.
- `fontNameFallbackCountMax` = 1 (from `AppConstants.swift`). Used identically in both original and new code via `Array(fallback.prefix(fontNameFallbackCountMax))`.
- `removeFontFallback()` calls `defaults[.desktopLyricsFontNameFallback].removeAll()` then sets `fontFallback = nil`. Matches original `removeFontFallbackAction`.
- HUD font writes to `lyricsWindowFontName` and `lyricsWindowFontSize`. Correct.
- `FontPickerCoordinator.changeFont(_:)` and `validModesForFontPanel(_:)` both `@objc` and implemented correctly. `manager.target = self` is set at button-click time, so the last-clicked picker coordinator correctly owns the font panel.
- `FontPickerButton.updateNSView` refreshes both `coordinator.currentFont` and `coordinator.onFontChange` — no stale closure capture possible.
- `ColorPicker(supportsOpacity: true)` used for all 6 color controls. Correct per D2.
- Color round-trip: `Color(NSColor)` → display → `NSColor(Color)` → `NSKeyedArchiver`. Alpha is preserved. `NSColor.withAlphaComponent` values survive the round-trip on macOS 11+.
- Pre-existing bug in `Extension.swift` line 94: `lyricsWindowFont` fallback uses `defaults[.desktopLyricsFontSize]` instead of `defaults[.lyricsWindowFontSize]`. Not introduced by Phase 5 — the migration calls `defaults.lyricsWindowFont` faithfully. Not fixed here (separate pre-existing issue).
- `onChange(of:) { _ in }` form: deprecated in macOS 14+ but consistent with the rest of the codebase and emits no errors. Not introduced by Phase 5.
- No fixes required.
- `plutil -lint`: OK (Phase 5 review build).
- Build: BUILD SUCCEEDED (Debug, 2026-05-23), no errors, no new warnings.

### Phase 7
- All removed files verified to have no remaining Swift references before deletion
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- Final result: `** BUILD SUCCEEDED **` (Debug, 2026-05-23)
- No dangling references: `grep` for `PreferenceViewController|AlphaColorWell|FilterKey|LyricsFilterKeyword|FontSelectTextField` in `*.swift` returned zero results
- Migration is complete

**Phase 7 review findings (2026-05-23)**

- Grep for all removed class/file names (`PreferenceViewController`, `PreferenceTabViewController`, `AlphaColorWell`, `FilterKey`, `LyricsFilterKeyword`, `FontSelectTextField`, and all 6 pane VCs) across `*.swift`, `*.storyboard`, `*.plist` in `LyricsX/`: zero hits. The only `FilterKey`/`lyricsFilterKeys` matches are the `UserDefaults.Key<[String]>` entry in `UserDefaultsKeys.swift` (line 80), `LyricsFilter.swift`, `FilterPreferencesView.swift`, and `UserDefaults.plist` — all legitimate, none related to the deleted `FilterKey.swift` type.
- Project file (`project.pbxproj`): `grep -c` for all 6 removed class/file names returned 0. `plutil -lint`: OK.
- Remaining `LyricsX/Preferences/` files: `GeneralPreferencesView.swift`, `PreferencesView.swift`, `SourcePreferencesView.swift`, `DisplayPreferencesView.swift`, `PreferenceWindowController.swift`, `FilterPreferencesView.swift`, `ShortcutPreferencesView.swift`, `LabPreferencesView.swift`, `SettingsSection.swift`, `NowPlayingApplicationListViewController.swift`. Correct — all new SwiftUI files plus the AppKit bridge (`NowPlayingApplicationListViewController`) and window controller.
- `Info.plist` `NSMainStoryboardFile` key: points to `Main` (the app's main menu/status-item storyboard, not Preferences). `Main.storyboard` still exists at `LyricsX/Base.lproj/Main.storyboard`. `Preferences.storyboard` has no Info.plist or project-file reference.
- Build: `** BUILD SUCCEEDED **` (Debug, 2026-05-23), no errors, no new warnings.
- No fixes required.

### Phase 6
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- `xcodebuild … build | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`: No errors
- Final result: `** BUILD SUCCEEDED **`

**Phase 6 review findings (2026-05-23)**

- `SearchSettings.sourcePriorityEnabled` get/set verified in `SearchSettings.swift` — `sourcePriorityEnabled` uses `defaults[.lyricsSourcePriorityEnabled]` with `nonmutating set`. Toggle `onChange` writes through correctly.
- `SearchSettings.sourcePriorityOrder` get/set verified — `[String]`, `nonmutating set`. `commitOrder()` writes then re-reads (defensive; no-op in normal operation). Correct.
- `availableLyricsSources` is a module-level `let` in `LyricsSelector.swift` — accessible from `SourcePreferencesView`. Correct.
- `LyricsSelector.shared.normalize(against:settings:)` called on `onAppear` (before loading state) and in `commitOrder()` after every mutation. Matches `PreferenceSourceViewController.viewDidLoad` + `savePriorityOrder` pattern exactly.
- `moveSource(from:to:)` `IndexSet`-based move: uses `sources.move(fromOffsets:toOffset:)` (Swift stdlib). `selectedIndex` tracking math verified for all three offset cases (moved row itself, row from above moving down, row from below moving up). Correct.
- `moveSelectedUp()` / `moveSelectedDown()`: swap at adjacent indices, update `selectedIndex`. Guard conditions on `nil` and boundary indices also applied to the buttons' `disabled()` modifier. Consistent.
- List dim/disable: `opacity(0.5).disabled(!sourcePriorityEnabled)` applied to both `sourceList` and `moveButtons`. Matches original `sourceTableView.alphaValue / isEnabled` behavior.
- `private let searchSettings = SearchSettings()` on a SwiftUI `View` struct: safe — `SearchSettings` is a struct wrapping `UserDefaults.standard` with `nonmutating set`. Consistent with `LabPreferencesView` and `PreferenceSourceViewController`. New instances across SwiftUI re-renders all share the same backing store.
- All 6 tabs in `PreferencesView` show real content — no placeholder panes remain. Tab order (General, Display, Shortcut, Filter, Lab, Source) preserved per D3.
- `onChange(of:) { newValue in }` single-argument form: consistent with rest of codebase (pre-macOS 14 API, no warnings at deployment target macOS 11).
- No fixes required.
- Build: BUILD SUCCEEDED (Debug, 2026-05-23), no errors, no new warnings.

**Phase 3 review findings (2026-05-23)**

- `@AppStorage("LyricsFilterEnabled")` and `@AppStorage("LyricsSmartFilterEnabled")` verified against `UserDefaultsKeys.swift` lines 78–79 — keys match exactly.
- `defaults[.lyricsFilterKeys]` is `Key<[String]>` — load returns `[String]`, save writes `[String]`. No `LyricsFilterKeyword` used anywhere. Correct per D2.
- `saveKeywords()` filters `{ !$0.isEmpty }` before writing — empty entries never persisted. Correct.
- `resetKeywords()` calls `defaults.remove(.lyricsFilterKeys)` then `loadKeywords()` — this calls `removeObject(forKey:)` via GenericID, restoring plist defaults on next read. Correct.
- `ForEach(keywords.indices)` binding: getter has `index < keywords.count` bounds check; setter has the same guard. Safe against SwiftUI deferred view teardown.
- `addKeyword()` saves immediately after appending `""` — `saveKeywords()` strips the empty entry, so only non-empty keywords land in defaults. The in-memory `keywords` retains the empty row for display. This is the intended behavior.
- `defaults` global is defined in `UserDefaultsKeys.swift` line 4 as `let defaults = UserDefaults.standard`. Accessible from `FilterPreferencesView`.
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- Build: BUILD SUCCEEDED (Debug, 2026-05-23), no errors.
- No fixes required.

**Phase 2 review findings (2026-05-23)**

- All 9 UserDefaults key strings verified against `UserDefaultsKeys.swift` lines 67–75 — all match exactly.
- `ShortcutRecorderView.makeNSView` sets `associatedUserDefaultsKey` correctly; `updateNSView` is a correct no-op.
- `ShortcutPreferencesView()` is at tag 2 in `PreferencesView.swift` — correct per D3 tab order.
- `plutil -lint LyricsX.xcodeproj/project.pbxproj`: OK
- Build: BUILD SUCCEEDED (Debug, 2026-05-23), no errors.
- No fixes required.
- Noted: `ShortcutSearchLyrics` had an `isRemovedDuringMASReview` runtime attribute in the storyboard. Not implemented in SwiftUI view. The original VC was also empty (attribute was on the `MASShortcutView` instance directly). Deferred to Phase 7 cleanup.

**Phase 1 review findings (2026-05-23)**

- All `@AppStorage` keys verified against `UserDefaultsKeys.swift` raw strings — all match exactly including the `DesktopLyricsEnableRomajin` typo.
- `toggleTouchBarCustomizationPalette(nil)` vs original `(sender)`: functionally identical; the sender arg is unused by the method body.
- `static func create()` exists and `AppContainer.preferencesWindowController` wiring is correct.
- `windowDidLoad` / `showWindow` lifecycle preserved; redundant `makeKeyAndOrderFront` in both is harmless (same as original storyboard behavior).
- No unrelated panes rewritten — storyboard VCs are untouched.

**Fix applied — NowPlayingApplicationListViewController dismiss (D2 revised)**:
- D2's original claim that `dismiss(nil)` propagates reliably through SwiftUI's sheet hosting chain is true on macOS 13+ but unreliable on macOS 11–12.
- Fixed in `LabPreferencesView.swift`: added a `Coordinator` to `NowPlayingApplicationListRepresentable` that retargets `closeButton` to a coordinator method. The coordinator calls the VC's `closeButtonAction` (which saves the app list and calls `dismiss(nil)`) then calls `onDismiss()` (which sets `showingNowPlayingSheet = false` directly). This ensures the SwiftUI binding is cleared on all supported macOS versions. Double-dismiss harmless — setting a Bool to its current value is idempotent.

## Decisions

### Phase 1 — D1: `onSubmit` availability gate
**Decision**: Wrapped `TextField.onSubmit` modifier in `@ViewBuilder` computed property gated on `#available(macOS 12, *)`. An explicit "Apply" button is provided as a reliable fallback on macOS 11.
**Rationale**: Deployment target is macOS 11+; `onSubmit` was introduced in macOS 12. The apply button is the primary commit path on both versions, so no behavior difference is visible to users.

### Phase 1 — D2: NowPlayingApplicationListViewController sheet bridging (revised in Phase 1 review)
**Decision**: Wrapped `NowPlayingApplicationListViewController` in a private `NSViewControllerRepresentable` (`NowPlayingApplicationListRepresentable`) with a `Coordinator`. The coordinator retargets `closeButton` to a coordinator method that (1) calls `vc.closeButtonAction` to save the app list, then (2) calls `onDismiss()` to set `showingNowPlayingSheet = false` directly.
**Rationale**: `dismiss(nil)` in an `NSViewControllerRepresentable` only reliably propagates to a SwiftUI `isPresented` binding on macOS 13+. On macOS 11–12 the binding stays `true`, blocking subsequent sheet presentations. The coordinator approach drives dismissal via the binding directly, with `closeButtonAction` still called for its data-save side effect. `dismiss(nil)` inside `closeButtonAction` is harmless — idempotent on all versions.

### Phase 1 — D3: Musixmatch token local state
**Decision**: `@AppStorage` doesn't support `String?` (optional). Used `@State var musixmatchToken: String` initialized from `SearchSettings.musixmatchToken ?? ""` on appear, writing back through `searchSettings.musixmatchToken` on commit (empty→nil collapse handled in `commitMusixmatchToken()`).
**Rationale**: Mirrors the existing `PreferenceLabViewController` pattern exactly, preserving the nil sentinel collapse behavior documented in the original code comments.

### Phase 2 — D1: `MASShortcutView` sizing
**Decision**: Fixed `ShortcutRecorderView` frame to `width: 160, height: 19`. Height 19 matches `MASShortcutViewStyleDefault` intrinsic height documented in `MASShortcutView.h`. Width 160 gives enough room for most shortcut descriptions without crowding the label.
**Rationale**: `MASShortcutView` does not report a useful `intrinsicContentSize` inside SwiftUI layout, so an explicit frame is necessary. The values match the original storyboard column widths.

### Phase 2 — D2: `SettingsRow` not used for shortcut rows
**Decision**: Used a local private `shortcutRow(_:key:)` method returning a plain `HStack` instead of `SettingsRow`. `SettingsRow` is generic over content which requires trailing-closure syntax; the helper keeps call sites concise and avoids boilerplate for a simple fixed-content pattern.
**Rationale**: Functionally equivalent — both produce `HStack { Text Spacer content }`. A private helper reduces repetition without adding a new exported type.

### Phase 3 — D1: Save on mutation, not on disappear
**Decision**: `saveKeywords()` is called after every add, remove, edit, and reset operation rather than deferring to a `viewWillDisappear` equivalent.
**Rationale**: SwiftUI has no reliable `viewWillDisappear` analogue on all supported macOS versions. Saving eagerly is simpler and prevents data loss if the window is force-quit or if the tab switches without the view being destroyed.

### Phase 3 — D2: `[String]` directly, no `LyricsFilterKeyword`
**Decision**: `FilterPreferencesView` uses `@State private var keywords: [String]` and reads/writes `defaults[.lyricsFilterKeys]` directly. `LyricsFilterKeyword` is not used.
**Rationale**: `LyricsFilterKeyword` existed only to support `NSArrayController` / Interface Builder bindings. With SwiftUI driving the list, plain strings are sufficient and cleaner.

### Phase 3 — D3: Regex indicator in keyword rows
**Decision**: Keywords with a `/` prefix display a small `.*` monospace badge and render in monospace font. No behavioral change.
**Rationale**: Makes it clear at a glance which entries are regex patterns without adding a separate column or control. The badge is read-only and never affects the stored value.

### Phase 3 — D4: Selection state with `@State var selectedIndex: Int?`
**Decision**: Selection is tracked with an optional integer index rather than a `Set<String>` or `List` selection binding.
**Rationale**: `List` selection on macOS 11 requires `Hashable` identifiers and SwiftUI `List` selection works differently across macOS versions. A plain `@State` integer sidesteps version compatibility issues while covering the only needed behavior: enabling/disabling the remove button and highlighting the active row.

### Phase 4 — D1: `LaunchAtLogin.Toggle` used directly
**Decision**: Used `LaunchAtLogin.Toggle("Launch and quit with player")` from the `LaunchAtLogin` package's SwiftUI support (`Toggle.swift`). Applied `.disabled(!canLaunchWithPlayer)` to replicate the storyboard's conditional-enable behavior. An `onChange(of: canLaunchWithPlayer)` handler enforces the constraint (sets the setting to false) when the player switches to Auto.
**Rationale**: The package ships a ready-made `LaunchAtLogin.Toggle` that binds to `LaunchAtLogin.observable` (an `ObservableObject`). Using it avoids bridging `LaunchAtLogin.kvo` manually in SwiftUI. The package is available on macOS 10.15+.

### Phase 4 — D2: NSOpenPanel via `beginSheetModal` with `NSApp.keyWindow` fallback
**Decision**: `chooseSavingPath()` tries `NSApp.keyWindow` and calls `beginSheetModal(for:completionHandler:)` if available; falls back to `runModal()` when no key window is present. The original AppKit code called `view.window!` which always had a window; from SwiftUI there's no direct window reference.
**Rationale**: `beginSheetModal` provides native sheet presentation attached to the preferences window. The `runModal()` fallback is safe and was also available in the original codebase's `chooseSavingPathAction`. In practice `NSApp.keyWindow` is the preferences window when the user clicks the button.

### Phase 4 — D3: Custom saving path popup with conditional second item
**Decision**: The `Picker` for saving path shows "Default (~/Music/LyricsX)" always and shows the custom directory name as tag-1 item only when `customDirectoryName` is non-empty. When the user chooses a directory, `commitSavingDirectory(_:)` sets both `customDirectoryName` and `savingPathPopUpIndex = 1`. When custom path is absent on appear, `savingPathPopUpIndex` is forced to 0.
**Rationale**: The original storyboard had a hidden `userPathMenuItem` that became visible once a custom path was chosen. The SwiftUI approach conditionally includes the second picker item, which is a natural SwiftUI equivalent. The `@AppStorage` binding handles persistence of the selected index automatically.

### Phase 4 — D4: Language picker uses `@State var languagePickerIndex` with gap at index 1
**Decision**: Language picker uses `@State var languagePickerIndex` (not `@AppStorage`) because the picker indices have a gap: 0 = System, 1 is unused (separator in original popup), 2+ = specific localizations. `@AppStorage` for `SelectedLanguage` isn't directly usable because it's a `String?` and requires mapping through `localizations`. State is loaded in `onAppear` and written via `applyLanguageSelection(_:)`.
**Rationale**: Exactly mirrors the original `chooseLanguageAction` index math: `localizations[selectedIdx - 2]` for a specific language, remove both keys for index 0. The gap at index 1 is preserved so that if the storyboard popup's separator behavior is referenced anywhere, the mapping remains consistent.

### Phase 4 — D5: Player constraints enforced via `onChange` + settings structs, not just `@AppStorage`
**Decision**: When `preferredPlayerIndex` changes, `enforcePlayerConstraints(for:)` is called — it writes to both the `PlayerSettings`/`PersistenceSettings` structs (which write to UserDefaults) and the local `@AppStorage` bindings. This ensures both the displayed UI state and the persisted values are in sync immediately.
**Rationale**: Writing only to `@AppStorage` would update the UI binding but not the typed settings structs (which may be observed by other subsystems at startup). Writing to both keeps the single-source-of-truth in UserDefaults while ensuring the SwiftUI binding reflects the forced value immediately.

### Phase 5 — D1: Native `ColorPicker` via view model (not `AlphaColorWell` bridge)
**Decision**: Used SwiftUI `ColorPicker(supportsOpacity: true)` bound to `@Published var` on `DisplayPreferencesViewModel`. The view model loads colors from `UserDefaults` as `NSColor?` on `onAppear`, converts to `SwiftUI.Color` for display, and converts back to `NSColor` for persistence via `NSColor(swiftUIColor)` on each `onChange`. `AlphaColorWell` is left untouched (Phase 7 cleanup candidate).
**Rationale**: `ColorPicker(supportsOpacity: true)` is the native SwiftUI equivalent of an alpha-enabled color well. `Color(NSColor)` and `NSColor(Color)` round-trip reliably on macOS 11+. The view model pattern (per Phase 0 — D5) is appropriate because NSColor defaults use a keyed-archive transformer and can't be accessed via `@AppStorage`.
**Issue encountered**: The GenericID subscript for `Key<NSColor>` returns `NSColor?` (not `NSColor`) because `NSColor` is not `DefaultConstructible`. Writing `Color(defaults[.desktopLyricsColor])` caused the Swift type-checker to backtrack and resolve the wrong subscript overload. Fix: explicit `let c: NSColor = defaults[.key] ?? fallback` binding before constructing `Color(c)`.

### Phase 5 — D2: `FontPickerCoordinator` NSObject subclass (not `FontSelectTextField` bridge)
**Decision**: Created a lightweight `FontPickerCoordinator: NSObject` that owns the `NSFontManager` target/action lifecycle, and a `FontPickerButton: NSViewRepresentable` that wraps a plain `NSButton`. `FontSelectTextField` is not used in the SwiftUI pane (Phase 7 cleanup candidate).
**Rationale**: `FontSelectTextField` only has `required init?(coder:)` — cannot be instantiated programmatically. The coordinator/button approach replicates the same NSFontManager/NSFontPanel behavior with no storyboard dependency. The `validModesForFontPanel` restriction is reproduced in `FontPickerCoordinator` via the NSFontManager target mechanism.

### Phase 6 — D1: List + `.onMove` with Up/Down button fallback
**Decision**: Used `List { ForEach … }.onMove(perform:)` with `.listStyle(.plain)` for the source list, plus explicit Move Up / Move Down buttons below the list.
**Rationale**: `.onMove` on macOS 13+ provides native drag handles in a plain `List`. On macOS 11–12, drag-to-reorder in a plain `List` is unreliable — move handles may not render. The Up/Down buttons are always visible and functional, giving users a reliable reorder path on all supported OS versions. `.listStyle(.bordered)` (macOS 12+) was considered and rejected since the deployment target is macOS 11.
**Alternative considered**: Bridging the original `NSTableView` with its pasteboard-based drag-and-drop. Rejected: adds `NSViewRepresentable` boilerplate and the original code is already available for fallback if needed.

### Phase 6 — D2: No separate `selectedRow` for `.onMove`
**Decision**: `selectedIndex` state is maintained for Up/Down button enable/disable. When `.onMove` fires, `selectedIndex` is updated to track the moved row using offset math.
**Rationale**: `List` selection binding and `.onMove` interact differently across macOS versions. Using a separate `@State` integer (same pattern as Phase 3 `FilterPreferencesView`) avoids binding conflicts and works consistently.

### Phase 5 — D3: Font fallback logic in view model (not view)
**Decision**: The desktop font fallback logic lives entirely in `DisplayPreferencesViewModel.desktopFontChanged(from:to:)`. The view only calls this method and reads `vm.fontFallback` for display.
**Rationale**: Keeps the view declarative. Mirrors the original `PreferenceDisplayViewController.fontChanged(from:to:sender:)` logic exactly, including the "remove new font from existing fallback before inserting old font" step.

## Resume instructions

**Migration complete.** All 7 phases finished as of 2026-05-23.

All 6 preference panes (General, Display, Shortcut, Filter, Lab, Source) are now pure SwiftUI. `PreferenceWindowController` creates the window programmatically. The storyboard and all legacy AppKit view controller files have been removed from both disk and the Xcode project. Build is clean.
