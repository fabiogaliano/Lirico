# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lirico is a macOS menu-bar application (`LSUIElement`) that automatically searches, downloads, and displays synchronized lyrics for the currently playing song. It supports multiple music players and lyrics sources, with desktop karaoke overlay and menu-bar lyrics display. This is a personally maintained fork of `ddddxxx/LyricsX`.

- **Platform**: macOS 15+ only
- **Language**: Swift 6 language mode (`SWIFT_VERSION = 6.0`); Swift 6.2 toolchain, i.e. Xcode 26+ (`swift-tools-version:6.2`)
- **Bundle ID**: `com.fabiogaliano.Lirico` (Release). Debug builds as `Lirico-Debug` / `dev.fabiogaliano.Lirico` so it runs side-by-side with the installed app.

## Build Commands

```bash
# Preferred: Makefile wrappers (build into ./build)
make build            # Debug
make release          # Release
make install          # Debug build → /Applications, relaunch (install-release for Release)

# Build (Debug)
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | xcsift

# Build (Release)
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Release build 2>&1 | xcsift
```

Builds are ad-hoc signed; there is no archive/notarization pipeline.

## Tests

The Xcode scheme has no tests. Search, restoration and sync logic lives in `LiricoPackage` and is covered by `LiricoFoundationTests` (Swift Testing):

```bash
cd LiricoPackage && swift test
```

CI (`.github/workflows/tests.yml`) runs `swift test --force-resolved-versions` on `macos-26` for pushes to `main` and PRs. `LiricoPackage/Package.resolved` is committed, so commit it whenever the package's dependencies change.

`scripts/lyrics-diag/diag.sh` runs the app's search queries, ranker and auto-pick against the current track with the app's saved settings (Release domain; `--debug` for the Debug one) — use it to debug search results. It ignores local lyrics, the blocklist, system-wide Now Playing, and which player the app already follows; its README lists the gaps.

## Linting & Formatting

Neither tool ships with the repo or runs in the build or CI; install them yourself (`brew install swiftlint swiftformat`). Both configs skip build output and the vendored `Lirico/Utility/Then.swift` and `Lirico/Utility/CXExtensions/`.

```bash
# SwiftLint (configured in .swiftlint.yml, line_length: 150)
swiftlint

# SwiftFormat (configured in .swiftformat, 4-space indent, LF line breaks)
swiftformat .
```

## Architecture

### Build System

Hybrid Xcode project + Swift Package Manager. The Xcode project (`Lirico.xcodeproj`) is the primary build entry point. It integrates `LiricoPackage/` as a local Swift package, and all third-party dependencies are managed via Xcode's SPM integration (no CocoaPods/Carthage).

### Targets

| Target | Purpose |
|---|---|
| `Lirico` | Main macOS app |
| `LiricoHelper` | LoginItem helper embedded in `Contents/Library/LoginItems/`, watches for music player launch and auto-starts the main app |

### Core Dependencies (via SPM)

- **LiricoKit** (`fabiogaliano/LiricoKit`, from 3.0.1) — lyrics search/parsing engine
- **MusicPlayer** (`MxIris-LyricsX-Project/MusicPlayer`, from 1.8.0) — music player abstraction layer
- **LiricoFoundation** (local package in `LiricoPackage/`) — re-exports LiricoKit and holds the testable domain logic: `Search/` (candidate evaluation + ranking, automatic and manual result policy), `Restoration/` (explicit-word restoration), `Rendering/` (line rendering, language tagging, Apple Music export text), `Player/` (auto-player choice), `Blocklist/` (blocked songs/albums as stored in defaults), `Sync/`

### App Internal Structure (`Lirico/`)

The app uses a **Combine-driven reactive architecture** wired in `AppContainer`, the composition root: `AppDelegate` builds one container, which constructs every service and controller and passes dependencies through initializers.

- **`Component/`** — Core services: `AppContainer`, `LyricsSession` (central lyrics state + search/management hub), `AutomaticLyricsSearch` / `LyricsSearchPipeline` (provider search), `LyricsDisplayCoordinator` (render snapshot for the line surfaces), `PlaybackClock` (line-index publisher), `PlayerHandle` (player adapter protocol), `SearchBlocklist`, and the `*Settings` wrappers over defaults. `LyricsSession` listens for track changes via Combine publishers, runs async lyrics searches (`AsyncSequence`), and exposes `currentLyrics` as a read-only publisher. Mutations flow through `select()` / `rejectCurrentLyrics(blocking:)` / `importLyrics()` commands. Apple-Music export lives in the pure `LyricsPersister` namespace.
- **`Controller/`** — Display controllers: `KaraokeLyricsController` (desktop karaoke overlay), `MenuBarLyricsController` (menu bar text), `LyricsSyncController` (Sync by Ear), `LyricsScrollback` (full-lyrics scroll view logic shared by the lyrics HUD and Sync by Ear)
- **`Search/`** — Manual lyrics search window (`SearchLyricsViewModel` + SwiftUI view)
- **`LyricsHUD/`** — Floating lyrics panel (`LyricsHUDViewController`)
- **`Preferences/`** — Settings panes (General, Lyrics, Appearance, Sources, Filter, Shortcuts) as grouped SwiftUI `Form`s built on `SettingsForm`; `PreferenceWindowController` hosts them in a toolbar-style `NSTabViewController`
- **`View/`** — Custom views: `KaraokeLabel`, `KaraokeLyricsView`, `ScrollLyricsView`
- **`Utility/`** — App constants/URLs/identifiers (`App*.swift`), `UserDefaultsKeys`, extensions, Combine utilities (`CXExtensions/`)

### Data Flow

1. `MusicPlayers.Selected.shared` (`SelectedPlayer.swift`, the one remaining singleton) follows the active player and publishes track/playback state; `SelectedPlayerHandle` wraps it and `AppContainer` injects it as a `PlayerHandle`
2. `LyricsSession` subscribes and runs `AutomaticLyricsSearch` on track change
3. Found lyrics stored as `@Published private(set) var currentLyrics` — written only by the session, never from outside
4. `LyricsSession.currentLyrics.didSet` pushes the lyrics into `PlaybackClock`, which emits the active line index; the session mirrors that into `@Published currentLineIndex`
5. `LyricsDisplayCoordinator` folds lyrics, line index and playback state into `snapshot`, which `KaraokeLyricsController` and `MenuBarLyricsController` render; the lyrics HUD and Sync by Ear read the session through `LyricsScrollback`

### Localization

- Managed via `.xcstrings` String Catalogs in `Lirico/Supporting Files/` (`Localizable`, `InfoPlist`)
- Crowdin (`crowdin.yml`) syncs those catalogs for collaborative translation

### Local Development with Dependencies

`LiricoPackage/Package.swift` switches to sibling checkouts (`../../LiricoKit`, `../../MusicPlayer`) via env vars: `LIRICO_USE_LOCAL_DEPENDENCY=1` enables both, `LIRICO_USE_LOCAL_LIRICOKIT=1` just LiricoKit.
