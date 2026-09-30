# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Lirico is a macOS menu-bar application (`LSUIElement`) that automatically searches, downloads, and displays synchronized lyrics for the currently playing song. It supports multiple music players and lyrics sources, with desktop karaoke overlay and menu-bar lyrics display. This is a personally maintained fork of `ddddxxx/LyricsX`.

- **Platform**: macOS 15+ only
- **Language**: Swift 5 (project setting), Swift 6.2 toolchain (Package.swift)
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

`scripts/lyrics-diag/diag.sh` runs the candidate/ranking pipeline against the current track with the app's real settings — use it to debug search results.

## Linting & Formatting

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
| `SwiftLint` | Aggregate target for running SwiftLint |

### Core Dependencies (via SPM)

- **LyricsKit** (`fabiogaliano/LyricsKit`, from 1.9.0) — lyrics search/parsing engine
- **MusicPlayer** (`MxIris-LyricsX-Project/MusicPlayer`, from 1.8.0) — music player abstraction layer
- **LiricoFoundation** (local package in `LiricoPackage/`) — re-exports LyricsKit and holds the testable domain logic: `Search/` (candidate evaluation + ranking), `Restoration/` (explicit-word restoration), `Sync/`

### App Internal Structure (`Lirico/`)

The app uses a **Combine-driven reactive architecture** with shared singletons:

- **`Component/`** — Core singletons: `LyricsSession` (central lyrics state + search/management hub), `AppDelegate`, `PlaybackClock` (line-index publisher), `PlayerHandle` (player adapter). `LyricsSession` listens for track changes via Combine publishers, runs async lyrics searches (`AsyncSequence`), and exposes `currentLyrics` as a read-only publisher. Mutations flow through `select()` / `clear()` / `importLyrics()` commands. Apple-Music export lives in the pure `LyricsPersister` namespace.
- **`Controller/`** — Display controllers: `KaraokeLyricsController` (desktop karaoke overlay), `MenuBarLyricsController` (menu bar text), `TouchBarLyricsController`, `LyricsSyncController` (Sync by Ear)
- **`Search/`** — Manual lyrics search window (`SearchLyricsViewModel` + SwiftUI view)
- **`TouchBar/`** — Touch Bar items (opt-in via Lab)
- **`LyricsHUD/`** — Floating lyrics panel (`LyricsHUDViewController`)
- **`Preferences/`** — Preference pane SwiftUI views (General, Display, Filter, Shortcut, Source, Lab); `PreferenceWindowController` creates the window programmatically via `NSHostingController`
- **`View/`** — Custom views: `KaraokeLabel`, `KaraokeLyricsView`, `ScrollLyricsView`
- **`Utility/`** — App constants/URLs/identifiers (`App*.swift`), `UserDefaultsKeys`, extensions, Combine utilities (`CXExtensions/`)

### Data Flow

1. `MusicPlayers.Selected.shared` publishes current track/playback state (wrapped in `PlayerHandle` and constructor-injected; no module-level player global)
2. `LyricsSession.shared` subscribes, triggers async lyrics search on track change
3. Found lyrics stored as `@Published private(set) var currentLyrics` — written only by the session, never from outside
4. `LyricsSession.currentLyrics.didSet` pushes the lyrics into `PlaybackClock`, which emits the active line index; the session mirrors that into `@Published currentLineIndex`
5. Display controllers (`KaraokeLyricsController`, `MenuBarLyricsController`, etc.) subscribe to lyrics + playback position to render synchronized output

### Localization

- Managed via `.xcstrings` String Catalogs in `Lirico/Supporting Files/` (`Localizable`, `InfoPlist`)
- Crowdin (`crowdin.yml`) syncs those catalogs for collaborative translation

### Local Development with Dependencies

`LiricoPackage/Package.swift` switches to sibling checkouts (`../../LyricsKit`, `../../MusicPlayer`) via env vars: `LIRICO_USE_LOCAL_DEPENDENCY=1` enables both, `LIRICO_USE_LOCAL_LYRICSKIT=1` just LyricsKit.
