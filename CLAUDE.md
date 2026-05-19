# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LyricsX is a macOS menu-bar application (`LSUIElement`) that automatically searches, downloads, and displays synchronized lyrics for the currently playing song. It supports multiple music players and lyrics sources, with desktop karaoke overlay and menu-bar lyrics display. This is a personally maintained fork of `ddddxxx/LyricsX`.

- **Platform**: macOS 11+ only
- **Language**: Swift 5 (project setting), Swift 6.2 toolchain (Package.swift)
- **Bundle ID**: `com.fabiogaliano.LyricsX`

## Build Commands

```bash
# Build (Debug)
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Debug build 2>&1 | xcsift

# Build (Release)
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Release build 2>&1 | xcsift

# Archive (triggers post-archive export + notarization script)
xcodebuild -project LyricsX.xcodeproj -scheme LyricsX -configuration Release archive
```

There are no automated tests configured in the Xcode scheme. The `LyricsXPackage` has an empty test target `LyricsXFoundationTests`.

## Linting & Formatting

```bash
# SwiftLint (configured in .swiftlint.yml, line_length: 150)
swiftlint

# SwiftFormat (configured in .swiftformat, 4-space indent, LF line breaks)
swiftformat .
```

## Architecture

### Build System

Hybrid Xcode project + Swift Package Manager. The Xcode project (`LyricsX.xcodeproj`) is the primary build entry point. It integrates `LyricsXPackage/` as a local Swift package, and all third-party dependencies are managed via Xcode's SPM integration (no CocoaPods/Carthage).

### Targets

| Target | Purpose |
|---|---|
| `LyricsX` | Main macOS app |
| `LyricsXHelper` | LoginItem helper embedded in `Contents/Library/LoginItems/`, watches for music player launch and auto-starts the main app |
| `SwiftLint` | Aggregate target for running SwiftLint |

### Core Dependencies (via SPM)

- **LyricsKit** (`MxIris-LyricsX-Project/LyricsKit`, branch: main) — lyrics search/parsing engine
- **MusicPlayer** (`MxIris-LyricsX-Project/MusicPlayer`, branch: master) — music player abstraction layer
- **LyricsXFoundation** (local package in `LyricsXPackage/`) — thin re-export wrapper: `@_exported import LyricsKit`

### App Internal Structure (`LyricsX/`)

The app uses a **Combine-driven reactive architecture** with shared singletons:

- **`Component/`** — Core singletons: `LyricsSession` (central lyrics state + search/management hub), `AppDelegate`, `PlaybackClock` (line-index publisher), `PlayerHandle` (player adapter). `LyricsSession` listens for track changes via Combine publishers, runs async lyrics searches (`AsyncSequence`), and exposes `currentLyrics` as a read-only publisher. Mutations flow through `select()` / `clear()` / `importLyrics()` commands. Apple-Music export lives in the pure `LyricsPersister` namespace.
- **`Controller/`** — Display controllers: `KaraokeLyricsController` (desktop karaoke overlay), `MenuBarLyricsController` (menu bar text), `TouchBarLyricsController`
- **`LyricsHUD/`** — Floating lyrics panel (`LyricsHUDViewController`)
- **`Preferences/`** — Preference pane ViewControllers (General, Display, Filter, Shortcut, Source, Lab)
- **`View/`** — Custom views: `KaraokeLabel`, `KaraokeLyricsView`, `ScrollLyricsView`
- **`Utility/`** — Global constants (`Global.swift`), extensions, Combine utilities (`CXExtensions/`)

### Data Flow

1. `MusicPlayers.Selected.shared` publishes current track/playback state (wrapped in `PlayerHandle` and constructor-injected; no module-level player global)
2. `LyricsSession.shared` subscribes, triggers async lyrics search on track change
3. Found lyrics stored as `@Published private(set) var currentLyrics` — written only by the session, never from outside
4. `LyricsSession.currentLyrics.didSet` pushes the lyrics into `PlaybackClock`, which emits the active line index; the session mirrors that into `@Published currentLineIndex`
5. Display controllers (`KaraokeLyricsController`, `MenuBarLyricsController`, etc.) subscribe to lyrics + playback position to render synchronized output

### Localization

- Managed via `.xcstrings` (Xcode String Catalogs) and legacy `.strings` files
- BartyCrouch (`.bartycrouch.toml`) syncs storyboard strings
- Crowdin (`crowdin.yml`) for collaborative translation

### Local Development with Dependencies

`LyricsXPackage/Package.swift` supports switching to local checkouts of `LyricsKit` and `MusicPlayer` via `local:` path overrides (disabled by default with `isEnabled: false`). Toggle these when developing against local forks of these libraries.
