# Preferences SwiftUI modernization follow-up

## Current status

- Current phase: COMPLETE
- Last completed phase: Phase 5 review — verified 2026-05-23
- Build status: PASS — BUILD SUCCEEDED (Debug clean build 0 errors/30 warnings, IS_FOR_MAS build SUCCEEDED, 2026-05-23, Phase 5 review)
- Known blockers: none — deferred work documented under D5.3 and D4.2

## Phase checklist

- [x] Phase 0 — Audit current diff and target bump plan
- [x] Phase 0 review
- [x] Phase 1 — Deployment target macOS 15+ modernization
- [x] Phase 1 review
- [x] Phase 2 — Known behavior regressions and bug fixes
- [x] Phase 2 review
- [x] Phase 3 — SwiftUI API cleanup
- [x] Phase 3 review
- [x] Phase 4 — Localization cleanup
- [x] Phase 4 review
- [x] Phase 5 — Final cleanup and verification
- [x] Phase 5 review

## Current migration diff summary

Migration commit: `e9e1398b feat(prefs): migrate preferences to SwiftUI`
Total: 27 files changed, 2592 insertions(+), 18489 deletions(-)

### Added — New SwiftUI preference pane views (7 files)

| File | Purpose |
|---|---|
| `Lirico/Preferences/PreferencesView.swift` | Root `TabView` with 6 tabs (General, Display, Shortcut, Filter, Lab, Source) |
| `Lirico/Preferences/SettingsSection.swift` | Reusable `SettingsSection<Content>` and `SettingsRow<Content>` layout primitives |
| `Lirico/Preferences/GeneralPreferencesView.swift` | General pane: player picker, saving path, search/display settings, language picker |
| `Lirico/Preferences/DisplayPreferencesView.swift` | Display pane: desktop lyrics + HUD fonts/colors/toggles; `DisplayPreferencesViewModel` for NSColor/NSFont bridging |
| `Lirico/Preferences/ShortcutPreferencesView.swift` | Shortcut pane: 9 `MASShortcutView` instances via `ShortcutRecorderView: NSViewRepresentable` |
| `Lirico/Preferences/FilterPreferencesView.swift` | Filter pane: filter toggles + editable keyword list with add/remove/reset |
| `Lirico/Preferences/LabPreferencesView.swift` | Lab pane: Touch Bar, Now Playing app list, Japanese furigana/romaji, Apple Music export, Musixmatch token |
| `Lirico/Preferences/SourcePreferencesView.swift` | Source pane: priority enable toggle + draggable/movable source list |

### Added — Documentation (2 files)

| File | Purpose |
|---|---|
| `docs/implementation/preferences-swiftui-migration.md` | Migration state document tracking all 7 migration phases |
| `docs/preferences-swiftui-modernization-followup-prompt.md` | Orchestrator prompt for this follow-up pass |

### Modified — Window controller and project (3 files)

| File | Purpose |
|---|---|
| `Lirico/Preferences/PreferenceWindowController.swift` | Replaced `StoryboardWindowController` conformance with programmatic `NSWindow` + `NSHostingController`; `static func create()` preserved |
| `Lirico/Component/LyricsSelector.swift` | Removed stale reference to `PreferenceSourceViewController` in a comment |
| `Lirico/Component/PersistenceSettings.swift` | Removed stale reference to `PreferenceGeneralViewController` in a comment |
| `Lirico.xcodeproj/project.pbxproj` | Added new SwiftUI file references; removed all deleted file references; `PBXVariantGroup` for storyboard removed |
| `Lirico/Supporting Files/Localizable.xcstrings` | New SwiftUI string labels extracted (+813 line diff); `mul.lproj/Preferences.xcstrings` content not migrated here |

### Deleted — Legacy storyboard controllers and views (12 files)

| File | Purpose (was) |
|---|---|
| `Lirico/Base.lproj/Preferences.storyboard` | Storyboard housing all 6 AppKit preference panes (2759 lines) |
| `Lirico/mul.lproj/Preferences.xcstrings` | Storyboard string catalog with translated preference strings (14891 lines, all locales) |
| `Lirico/Preferences/PreferenceViewController.swift` | Base classes `PreferenceViewController` and `PreferenceTabViewController` |
| `Lirico/Preferences/PreferenceGeneralViewController.swift` | AppKit General pane VC (134 lines) |
| `Lirico/Preferences/PreferenceDisplayViewController.swift` | AppKit Display pane VC (56 lines) |
| `Lirico/Preferences/PreferenceShortcutViewController.swift` | AppKit Shortcut pane VC (5 lines, empty body) |
| `Lirico/Preferences/PreferenceFilterViewController.swift` | AppKit Filter pane VC (30 lines) |
| `Lirico/Preferences/PreferenceLabViewController.swift` | AppKit Lab pane VC (38 lines) |
| `Lirico/Preferences/PreferenceSourceViewController.swift` | AppKit Source pane VC (111 lines) |
| `Lirico/Preferences/AlphaColorWell.swift` | Custom NSColorWell subclass supporting alpha; replaced by `ColorPicker(supportsOpacity: true)` |
| `Lirico/Preferences/FilterKey.swift` | `LyricsFilterKeyword: NSObject` for NSArrayController bindings; replaced by plain `[String]` |
| `Lirico/View/FontSelectTextField.swift` | Custom NSTextField+NSFontManager for font selection; replaced by `FontPickerCoordinator`/`FontPickerButton` |

## Decisions

No production decisions made in Phase 0. Decisions will be added by Phase 1+ subagents.

### Phase 1 decisions

**D1.1 — Upstream dependency platform minimums**

- Phase: Phase 1
- Decision: Confirmed both upstream SPM dependencies support macOS platforms well below 15. LyricsKit (pinned `44588c2c`, v1.8.0) declares `.macOS(.v11)`; MusicPlayer (pinned `f220ac6c`, v1.8.0) declares `.macOS(.v10_15)`. A downstream consumer may set a higher minimum than its dependencies, so bumping `LiricoPackage/Package.swift` to `.macOS(.v15)` is valid.
- Alternatives considered: Block the bump if any dependency declared a minimum > 15 (not the case here).
- Rationale: Both deps are at v11 or v10.15; bumping to v15 is purely a consumer-side restriction with no impact on dependency resolution.
- Risk: Low. If a future dependency version raises its own minimum above 15, SPM will flag it at that time.
- Deferred follow-up: None.

**D1.2 — SwiftLint aggregate target deployment target**

- Phase: Phase 1
- Decision: Bumped SwiftLint aggregate target `MACOSX_DEPLOYMENT_TARGET` from `10.11` to `15.0` (lines 899 and 958 in project.pbxproj) along with the compiled targets.
- Alternatives considered: Leave at 10.11 (no practical effect since it's a script-phase-only aggregate); set to project default.
- Rationale: Consistency — all six `MACOSX_DEPLOYMENT_TARGET` entries now read `15.0`. The SwiftLint aggregate has no compiled sources, so the deployment target is cosmetic only. Mixed values (10.11 vs 15.0) would be confusing on inspection.
- Risk: Zero. Script-phase aggregate targets do not compile Swift or link against the SDK.
- Deferred follow-up: None.

**D1.3 — macOS 11 references in historical docs left in place**

- Phase: Phase 1
- Decision: Left all `macOS 11` references in `docs/prompt.md` and `docs/implementation/preferences-swiftui-migration.md` unchanged. These documents record the original migration decisions and constraints, which are historically accurate. Modifying them would erase rationale context.
- Alternatives considered: Update all historical docs to say 15+.
- Rationale: The orchestrator prompt explicitly excludes these two state docs from the "macOS 11" scrub sweep. The migration doc records why certain compatibility branches were added; updating it to say 15+ would make the rationale incoherent.
- Risk: Low. Readers might be briefly confused, but the Phase 1 state doc updates make it clear the current minimum is 15+.
- Deferred follow-up: Phase 3 will remove the actual compatibility branches these docs describe, at which point the migration doc rationale entries become moot.

### Phase 2 decisions

**D2.1 — MAS review condition reproduced from IBInspection.swift**

- Phase: Phase 2
- Decision: Reproduced the `isRemovedDuringMASReview` condition exactly as defined in `IBInspection.swift` lines 33–43.
  - Source-of-truth (IBInspection.swift): `#if IS_FOR_MAS` / `if newValue, defaults[.isInMASReview] != false` / `removeFromSuperview()`
  - In SwiftUI (ShortcutPreferencesView.swift): `#if IS_FOR_MAS` / `if defaults[.isInMASReview] != false { EmptyView() } else { shortcutRow(…) }` / `#else` / `shortcutRow(…)` / `#endif`
  - The storyboard set `isRemovedDuringMASReview = true` on the MASShortcutView, so `newValue` was always `true`; this term is elided in the SwiftUI form (replaced by the `#if`/`#else` structure itself).
- Alternatives considered: use `.opacity(0).disabled(true)` for hide instead of conditional inclusion. Rejected — `removeFromSuperview()` is omission, not hiding, so `EmptyView()` / conditional branch is the correct equivalent.
- Rationale: Exact semantic parity with IBInspection.swift. The condition `defaults[.isInMASReview] != false` hides the row when the key is `true` or not set (nil), which matches the original `Bool?` key semantics.
- Risk: None — IS_FOR_MAS is not currently defined in any build configuration, so only the `#else` branch compiles in all current builds.
- Deferred follow-up: None.

**D2.2 — Migration doc Phase 0 review checkbox handling**

- Phase: Phase 2
- Decision: Left the `[ ] Phase 0 review` checkbox unchecked and added a blockquote note immediately below it pointing to the modernization follow-up doc, rather than marking it `[x]`.
- Alternatives considered: (a) Mark `[x]` since Phase 0 review was effectively performed during the follow-up pass. (b) Add note and leave unchecked (chosen). (c) Rewrite the entire section.
- Rationale: The migration doc records what happened during the original migration. Phase 0 review did not happen at migration time. Marking it `[x]` would falsify the historical record. A corrective note is the least-invasive accurate representation. The Phase 0 review that was done is properly documented in the follow-up state doc.
- Risk: Low. A reader who only reads the migration doc will see the unchecked box and the note, giving them accurate context.
- Deferred follow-up: None.

**D2.3 — IS_FOR_MAS not defined in any project build configuration**

- Phase: Phase 2
- Decision: `IS_FOR_MAS` is referenced only in `IBInspection.swift` (3 occurrences) and now `ShortcutPreferencesView.swift` (1 occurrence). It is not defined in `SWIFT_ACTIVE_COMPILATION_CONDITIONS` or `GCC_PREPROCESSOR_DEFINITIONS` in `project.pbxproj`, and there are no `.xcconfig` files in the repository. This flag would need to be added manually to a Release build configuration when submitting to the MAS.
- Alternatives considered: Define `IS_FOR_MAS` in the project now. Rejected — that is out of Phase 2 scope and not requested.
- Rationale: The `#if IS_FOR_MAS` pattern is a pre-existing convention in the codebase. The Phase 2 fix correctly mirrors it. The flag absence means the MAS-hiding branch is never active in current builds, which is the same situation that existed with the old storyboard code.
- Risk: Low. Documented for future MAS submission setup.
- Deferred follow-up: Whoever prepares a MAS build should add `IS_FOR_MAS` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for the MAS Release configuration.

### Phase 4 decisions

**D4.1 — Junk keys removed from Localizable.xcstrings**

- Phase: Phase 4
- Decision: Removed exactly 3 keys from `Lirico/Supporting Files/Localizable.xcstrings`: `""` (empty string), `".*"`, and `"%lld"`. All three had empty entries `{}` with no localizations.
  - `""` (empty string): No source-code reference as a `Text("")` or `String(localized: "")` literal anywhere in `Lirico/`, `LiricoHelper/`, or `LiricoPackage/`. Pure extraction artifact.
  - `".*"`: Referenced as `Text(".*")` in `FilterPreferencesView.swift` line 88 — a monospace regex-badge visual indicator. It is user-facing text in the sense that it is displayed, but it is a fixed technical notation (a regex wildcard symbol) that is not translatable and has no localizations. Removing it from the catalog is safe; SwiftUI will fall back to the literal string itself.
  - `"%lld"`: Found only in the xcstrings file itself (the key being deleted). No Swift source reference. Likely extracted by Xcode from a NumberFormatter or `%lld`-format string in a `LocalizedStringKey` context. Not intentionally user-facing.
- Alternatives considered: Keep `".*"` since it is referenced from source. Rejected — the key has no translations, the displayed string is a fixed technical symbol with no meaningful localization surface, and removing the xcstrings entry causes SwiftUI to display the literal `".*"` string unchanged (identical runtime behavior).
- Rationale: All three keys are extraction artifacts with no translations. Keeping them would add catalog noise with zero benefit.
- Risk: Minimal. SwiftUI falls back to the literal string when a key is absent from the catalog, so runtime display is unchanged.
- Deferred follow-up: None.

**D4.2 — Deferred translation salvage for deleted mul.lproj/Preferences.xcstrings**

- Phase: Phase 4
- Decision: Did NOT attempt automated translation salvage from the deleted `Lirico/mul.lproj/Preferences.xcstrings`. The old file is recoverable from git at commit `e9e1398bada999be8280bb0e67f50b16d53fa27f~1` (the commit just before the migration commit `e9e1398b`). The 18 affected locales are: `ar`, `base`, `de`, `en`, `es`, `fa`, `fr`, `id`, `it`, `ja`, `ko`, `nl`, `pl`, `pt`, `ru`, `uk`, `zh-Hans`, `zh-Hant`.
  - The old file used storyboard-specific string identifiers (e.g. `atC-aF-Wgo.title`) as keys. The new SwiftUI views use plain English source strings as keys. There is no safe automated mapping between the two key formats.
  - Attempting to map old translations to new keys would require manually matching English source strings between the storyboard IDs and the new SwiftUI literals — a high-risk task prone to mismatches and silent corruption of translations.
- Alternatives considered: Attempt automated salvage via {storyboard-id → english-text} lookup against the old file's English locale. Rejected — too risky given the key-format mismatch; no tooling in the current workflow supports this.
- Rationale: Preserving localization correctness over attempting incomplete salvage. After junk-key cleanup, `Localizable.xcstrings` contains 65 keys; only a small existing/general subset has localizations, and the bulk of the new SwiftUI Preferences strings still need a dedicated localization pass. A future salvage pass can recover old translations properly.
- Risk: Low. The app's Preferences UI was previously translated but the new SwiftUI panes are not yet translated. This is a known regression from the migration; this phase does not worsen it. The old translations are fully preserved in git history.
- Deferred follow-up: A future salvage pass should: (1) `git show e9e1398bada999be8280bb0e67f50b16d53fa27f~1:'Lirico/mul.lproj/Preferences.xcstrings'` to recover the old file; (2) build a `{source_english → {locale: translation}}` dict using the old file's English locale as the source-language lookup; (3) walk `Lirico/Supporting Files/Localizable.xcstrings` and merge translations where the new SwiftUI source string exactly matches the old storyboard English text; (4) manually verify all merged translations before committing.

### Phase 5 decisions

**D5.1 — Stale `<!--Preferences-->` scene removed from Main.storyboard**

- Phase: Phase 5
- Decision: Removed the entire `<scene sceneID="TYy-pe-r3R">` block (8 lines) from `Lirico/Base.lproj/Main.storyboard`. The block contained a `<controllerPlaceholder storyboardName="Preferences" id="W7f-Zh-TfF">` — a reference to the deleted `Preferences.storyboard`. This was the source of the `"Preferences" is unreachable` build warning seen in Phase 1–4 build logs. The scene had no connections from any other scene (confirmed by grepping for both scene ID `TYy-pe-r3R` and controller ID `W7f-Zh-TfF` — zero external references).
- Alternatives considered: Leave in place (keep the warning). Rejected — dead XML that causes a build warning and is misleading to maintainers.
- Rationale: The `Preferences.storyboard` it referenced was deleted in the migration. The scene is entirely unreachable dead code. Removing it eliminates the warning and improves storyboard clarity.
- Risk: Zero. The scene was unreachable and unconnected. No segues, no menu items, no programmatic references to any of its IDs.
- Deferred follow-up: None.

**D5.2 — `CLAUDE.md` Preferences architecture line updated to reflect SwiftUI**

- Phase: Phase 5
- Decision: Updated the `Preferences/` description in `CLAUDE.md` from "Preference pane ViewControllers" to "Preference pane SwiftUI views; `PreferenceWindowController` creates the window programmatically via `NSHostingController`".
- Alternatives considered: No change (leave stale). Rejected — this is the project instructions file, which should reflect current reality.
- Rationale: The migration replaced all AppKit ViewControllers with SwiftUI views. The old description would mislead future agents and developers about the architecture.
- Risk: Zero. Documentation-only change.
- Deferred follow-up: None.

**D5.3 — macOS 11/12 in AppDelegate.swift left in place**

- Phase: Phase 5
- Decision: `AppDelegate.swift:176` contains `if #available(macOS 11, *)`. This file is out of Preferences scope and is not a Preferences modernization artifact. The guard may still be meaningful for code paths that were not part of the SwiftUI migration.
- Alternatives considered: Remove the guard since deployment target is now macOS 15+. Deferred — AppDelegate.swift was not part of any migration phase and changing it is outside Phase 5 scope.
- Rationale: Phase 5 scope is limited to stale Preferences-migration artifacts. AppDelegate.swift guards require separate, careful review.
- Risk: Low. Leaving a now-dead guard is safe; removing it without review could hide a conditional that was masking a bug.
- Deferred follow-up: A separate cleanup pass should audit `AppDelegate.swift:176` and any other `if #available(macOS 11/12/13, *)` guards in AppDelegate against the macOS 15+ deployment target and remove any that are now unconditionally true.

**D5.4 — Non-Preferences onChange sites not touched**

- Phase: Phase 5
- Decision: Grepping for `onChange(of:)` in the full project found only the 13 Preferences sites (all already updated to modern form in Phase 3). No additional deprecated `onChange(of:)` sites exist outside Preferences in the current codebase.
- Alternatives considered: N/A — no hits to act on.
- Rationale: The broader project has no deprecated `onChange(of:)` sites to address.
- Risk: None.
- Deferred follow-up: None.

**D5.5 — Corrective note added to preferences-swiftui-migration.md Phase 6 review**

- Phase: Phase 5
- Decision: Added a one-line blockquote corrective note to the Phase 6 review findings entry in `docs/implementation/preferences-swiftui-migration.md` at the `onChange(of:)` single-argument form observation. The note points to the modernization follow-up doc. The `#available(macOS 12, *)` guard reference in Phase 1 D1 of the same doc was left unchanged — it records the original migration decision and is explicitly out of scope per D1.3.
- Alternatives considered: Rewrite the affected sections to say macOS 15+. Rejected per D1.3 — historical rationale must be preserved.
- Risk: None.
- Deferred follow-up: None.

### Phase 3 decisions

**D3.1 — onChange form selection: two-arg vs zero-arg**

- Phase: Phase 3
- Decision: Used two-arg form `{ _, newValue in ... }` for closures that use the bound parameter (GeneralPreferencesView.swift all 6 sites, SourcePreferencesView.swift 1 site). Used zero-arg form `{ vm.save...() }` for all 6 DisplayPreferencesView.swift sites because those closures explicitly discarded the value with `{ _ in }` — they only need to fire a side-effect, which the zero-arg form expresses more clearly.
- Alternatives considered: Using two-arg form `{ _, _ in vm.save...() }` for the Display closures. Rejected — zero-arg form is more idiomatic when the value is not used.
- Rationale: Both forms are semantically equivalent for those sites; zero-arg minimizes noise.
- Risk: None — both forms available and correct on macOS 14+.
- Deferred follow-up: None.

**D3.2 — LabPreferencesView `NowPlayingApplicationListRepresentable` Coordinator not simplified**

- Phase: Phase 3
- Decision: Left the `Coordinator`/`onDismiss` pattern in place. The macOS 11/12 unreliability comment was removed, but the pattern itself was kept because it remains valid and safe on macOS 15. The pattern correctly separates VC close logic from SwiftUI dismissal — removing it would require verifying that `NSViewControllerRepresentable` dismiss-via-presentingViewController works reliably for this specific sheet on macOS 15, which is speculative refactor territory.
- Alternatives considered: Replace Coordinator with direct `.sheet(onDismiss:)` / `dismiss(nil)` path.
- Rationale: Preserving existing behavior. The pattern works, the compat rationale comment is gone, and the code is now just normal macOS 15+ code without any guard-related cruft.
- Risk: Low. The Coordinator stays but no longer claims to be a workaround.
- Deferred follow-up: Could be simplified in a future cleanup pass if desired.

**D3.3 — SourcePreferencesView Up/Down buttons kept**

- Phase: Phase 3
- Decision: Removed the macOS 11–12 drag-handles comment but kept the Up/Down move buttons themselves. The comment implied the buttons were a fallback for macOS 11/12 — but on macOS 15+ drag-to-reorder works natively, so the buttons are now a redundant but harmless UX enhancement (keyboard-accessible reordering). Keeping them avoids any behavior regression.
- Alternatives considered: Delete the Up/Down buttons since drag-to-reorder is reliable on macOS 15.
- Rationale: Removing functional UI is speculative and outside Phase 3 scope. The comment was the dead code; the buttons are live code that may be useful to keyboard users.
- Risk: None.
- Deferred follow-up: Phase 5 or future cleanup could consider removing the buttons if drag-only is acceptable.

## Unknowns resolved autonomously

No unknowns resolved in Phase 0. See Phase 2 decisions D2.3 for the IS_FOR_MAS flag finding.

### Phase 4 unknowns

**U4.1 — `".*"` key: user-facing symbol vs. junk extraction artifact**

- Unknown: `Text(".*")` at `FilterPreferencesView.swift:88` is a displayed string. Is it user-facing enough to warrant a localization entry?
- Resolution: Removed. The string `".*"` is a fixed technical notation (regex wildcard) that is not linguistically translatable. No locale would meaningfully differ from the English `".*"`. The fact that it had zero localizations in the catalog (and presumably none were planned) confirms it was an unintentional extraction artifact. SwiftUI falls back to the literal, so runtime behavior is unchanged.
- Risk: Zero runtime impact. A future translator workflow (BartyCrouch/Crowdin) can re-extract it if a translator wishes to transliterate the symbol for a locale that uses non-ASCII typography — but that is extremely unlikely.

## Phase 1–5 proposed file list

### Phase 1 — Deployment target macOS 15+ modernization

Goal: raise minimum deployment target from macOS 11 to macOS 15.

| File | Change | Rationale |
|---|---|---|
| `Lirico.xcodeproj/project.pbxproj` | Change `MACOSX_DEPLOYMENT_TARGET` from `11.0` to `15.0` for Lirico (Debug + Release) and LiricoHelper (Debug + Release) configs (lines 989, 1015, 1036, 1057) | Main app and helper both at 11.0; both need bump |
| `LiricoPackage/Package.swift` | Change `.macOS(.v11)` to `.macOS(.v15)` (line 57) | Package platform must match or stay below app target; bumping to 15 enables modern Swift concurrency in the package if needed |
| `README.md` | Update "macOS 11+" to "macOS 15+" in Requirements section (line 30) | Docs must reflect new minimum |
| `CLAUDE.md` | Update "macOS 11+ only" (line 9) to "macOS 15+ only" | Project instructions must reflect new minimum |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Record Phase 1 complete | State doc update |

Note: Two build configs at lines 899 and 958 show `MACOSX_DEPLOYMENT_TARGET = 10.11` — these appear to be the SwiftLint aggregate target configs; verify before changing.

### Phase 2 — Known behavior regressions and bug fixes

Goal: fix two known bugs and mark migration doc Phase 0 review.

| File | Change | Rationale |
|---|---|---|
| `Lirico/Preferences/ShortcutPreferencesView.swift` | Add conditional view hiding for `ShortcutSearchLyrics` row when `#if IS_FOR_MAS` and `defaults[.isInMASReview] != false` | Old storyboard had `isRemovedDuringMASReview` runtime attribute on the `MASShortcutView` for this key; semantics from `IBInspection.swift` lines 33–43 must be reproduced |
| `Lirico/Utility/Extension.swift` | Fix `lyricsWindowFont` fallback at line 94: change `defaults[.desktopLyricsFontSize]` to `defaults[.lyricsWindowFontSize]` | Pre-existing bug confirmed at line 94: fallback uses wrong size key |
| `docs/implementation/preferences-swiftui-migration.md` | Mark Phase 0 review checkbox as `[x]` (was `[ ]`) with a note that it was reviewed during the follow-up pass | Migration marked complete but Phase 0 review checkbox left unchecked |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Record Phase 2 decisions/unknowns | State doc update |

### Phase 3 — SwiftUI API cleanup for macOS 15+

Goal: replace deprecated `onChange(of:)` single-argument form; remove macOS 11/12 compat branches.

**`onChange(of:)` sites by file (13 total):**

| File | Count | Lines |
|---|---|---|
| `Lirico/Preferences/GeneralPreferencesView.swift` | 6 | 76, 81, 108, 157, 180, 197 |
| `Lirico/Preferences/DisplayPreferencesView.swift` | 6 | 211, 216, 221, 226, 252, 257 |
| `Lirico/Preferences/SourcePreferencesView.swift` | 1 | 25 |

**macOS 11/12 compatibility branches to remove:**

| File | Line | Change |
|---|---|---|
| `Lirico/Preferences/LabPreferencesView.swift` | 11, 46, 150–159 | Remove `if #available(macOS 12, *)` guard; use `onSubmit` unconditionally (macOS 15 always has it); remove else branch and comment |
| `Lirico/Preferences/LabPreferencesView.swift` | 11, 46 | Remove macOS 11–12 dismissal workaround comment once target is 15+ |
| `Lirico/Preferences/SourcePreferencesView.swift` | 44–46 | Remove macOS 11–12 drag-handles comment; keep Up/Down buttons (still useful for keyboard reordering) |

**`onChange(of:)` migration pattern** (macOS 14+ two-argument form):
```swift
// Before (deprecated):
.onChange(of: someValue) { newValue in ... }
// After (macOS 14+):
.onChange(of: someValue) { _, newValue in ... }
// For fire-and-forget (no new value needed):
.onChange(of: someValue) { _, _ in doSomething() }
```

Files to edit in Phase 3:
- `Lirico/Preferences/GeneralPreferencesView.swift`
- `Lirico/Preferences/DisplayPreferencesView.swift`
- `Lirico/Preferences/SourcePreferencesView.swift`
- `Lirico/Preferences/LabPreferencesView.swift`
- `docs/implementation/preferences-swiftui-modernization-followup.md`

### Phase 4 — Localization cleanup

Goal: remove junk keys from `Localizable.xcstrings`; decide fate of deleted `mul.lproj/Preferences.xcstrings`.

**Confirmed junk keys (3 keys, no translations):**

| Key | Status | Action |
|---|---|---|
| `""` (empty string) | No localizations | Delete — clearly accidental extraction artifact |
| `".*"` | No localizations | Delete — extracted from regex badge `Text(".*")` in `FilterPreferencesView.swift` line 88; should not be a localization key |
| `"%lld"` | No localizations | Delete — extracted from NumberFormatter; not user-facing |

**Note on `mul.lproj/Preferences.xcstrings` deletion:** The 14891-line storyboard string catalog was deleted as part of the migration. Its keys were storyboard-specific identifiers (e.g. `atC-aF-Wgo.title`) not plain-English keys. The new SwiftUI views use plain-English strings directly. There is no safe automated mapping between old catalog IDs and new SwiftUI strings. Deferred translation migration for the post-cleanup `Localizable.xcstrings` keys (65 total after the 3 junk-key removals) is the safe path.

Files to edit in Phase 4:
- `Lirico/Supporting Files/Localizable.xcstrings`
- `docs/implementation/preferences-swiftui-modernization-followup.md`

### Phase 5 — Final cleanup and verification

Goal: verify no stale references; run final build; record outcome.

Checks to run:
- Stale Swift refs to deleted classes/files (use narrow, unique identifiers — `FilterKey` as a bare word falsely matches live `lyricsFilterKeys` usages):
  `grep -REn 'AlphaColorWell|LyricsFilterKeyword|FontSelectTextField|PreferenceViewController|PreferenceTabViewController|PreferenceGeneralViewController|PreferenceDisplayViewController|PreferenceShortcutViewController|PreferenceFilterViewController|PreferenceLabViewController|PreferenceSourceViewController' Lirico/ LiricoHelper/ LiricoPackage/ --include='*.swift'` → expect 0 hits
- Stale storyboard reference (separate check, including non-Swift files):
  `grep -REn 'Preferences\.storyboard|Preferences\.xcstrings|mul\.lproj/Preferences' Lirico/ Lirico.xcodeproj/` → expect 0 hits (the `mul.lproj/Main.xcstrings` line in `project.pbxproj` is legitimate and intentionally not matched)
- Deprecated single-argument `onChange(of:)` forms (CANNOT use a bare `grep -n 'onChange(of:)'` — the modern macOS 14+ two-arg `{ _, newValue in ... }` and zero-arg forms still contain the literal `onChange(of:)`; instead verify via build warnings):
  `xcodebuild ... build 2>&1 | grep -E "onChange.*deprecated"` → expect 0 hits
  Optionally also list all sites for manual shape inspection: `grep -REn '\.onChange\(of:' Lirico/Preferences/` → expect every closure to be `{ _, name in ... }` or `{ ... }` (no bare `{ name in ... }` single-arg form)
- `grep -REn 'macOS 1[12]' Lirico/Preferences/` → expect 0 hits
- `grep -n MACOSX_DEPLOYMENT_TARGET Lirico.xcodeproj/project.pbxproj` → expect only `15.0` for all targets
- `python3 -m json.tool "Lirico/Supporting Files/Localizable.xcstrings" >/dev/null` → expect OK
- `plutil -lint Lirico.xcodeproj/project.pbxproj` → expect OK
- Full build → expect BUILD SUCCEEDED, 0 errors

Files to edit in Phase 5:
- `docs/implementation/preferences-swiftui-modernization-followup.md`
- Any stale refs found during checks

## Changed files by phase

### Phase 0

- Added: `docs/implementation/preferences-swiftui-modernization-followup.md` (this document)

### Phase 1

| File | Change | Rationale |
|---|---|---|
| `Lirico.xcodeproj/project.pbxproj` | `MACOSX_DEPLOYMENT_TARGET`: 6 occurrences changed — 4× `11.0` (Lirico + LiricoHelper Debug/Release) → `15.0`; 2× `10.11` (SwiftLint aggregate Debug/Release) → `15.0` | App and helper require macOS 15+; SwiftLint aggregate bumped for consistency |
| `LiricoPackage/Package.swift` | `platforms: [.macOS(.v11)]` → `platforms: [.macOS(.v15)]` | Package must declare at least the minimum the app requires |
| `CLAUDE.md` | `macOS 11+ only` → `macOS 15+ only` in Platform line | Project instructions must reflect current minimum |
| `README.md` | `macOS 11+` → `macOS 15+` in Requirements section | User-facing docs must reflect current minimum |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Phase 1 status, checklist, decisions, verification log, resume instructions updated | State doc update |

### Phase 2

| File | Change | Rationale |
|---|---|---|
| `Lirico/Preferences/ShortcutPreferencesView.swift` | Added `#if IS_FOR_MAS` / `if defaults[.isInMASReview] != false` conditional around the "Search lyrics" shortcut row in `lyricsActionsSection` | Restores `isRemovedDuringMASReview` storyboard behavior lost during migration; exact semantic match to IBInspection.swift lines 33–43 |
| `Lirico/Utility/Extension.swift` | Fixed `lyricsWindowFont` fallback at line 94: `defaults[.desktopLyricsFontSize]` → `defaults[.lyricsWindowFontSize]` | Pre-existing bug: fallback was using the desktop lyrics font size instead of the lyrics window font size |
| `docs/implementation/preferences-swiftui-migration.md` | Added corrective blockquote note below `[ ] Phase 0 review` checkbox pointing to the modernization follow-up doc | Phase 0 review was deferred at migration time; note records accurate history without falsifying the checkbox |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Phase 2 status, checklist, decisions (D2.1–D2.3), verification log, resume instructions updated | State doc update |

### Phase 3

| File | onChange sites updated | Compat branches removed | Comments removed |
|---|---|---|---|
| `Lirico/Preferences/GeneralPreferencesView.swift` | 6 (all → two-arg `{ _, newValue in }`) | 0 | 0 |
| `Lirico/Preferences/DisplayPreferencesView.swift` | 6 (all → zero-arg `{}`) | 0 | 0 |
| `Lirico/Preferences/SourcePreferencesView.swift` | 1 (→ two-arg `{ _, enabled in }`) | 0 | 1 (macOS 11–12 drag-handles comment) |
| `Lirico/Preferences/LabPreferencesView.swift` | 0 | 1 (`if #available(macOS 12, *)` guard around `.onSubmit`) | 2 (macOS 11–12 comments in doc + inline) |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | — | — | State doc update |

### Phase 4

| File | Change | Rationale |
|---|---|---|
| `Lirico/Supporting Files/Localizable.xcstrings` | Removed 3 junk keys: `""`, `".*"`, `"%lld"` (all had empty `{}` entries, no localizations); key count 68 → 65 | Extraction artifacts from SwiftUI migration with no translations; catalog is now clean |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Phase 4 status, checklist, decisions (D4.1, D4.2), unknowns (U4.1), verification log, resume instructions updated | State doc update |

### Phase 5

| File | Change | Rationale |
|---|---|---|
| `Lirico/Base.lproj/Main.storyboard` | Removed stale `<!--Preferences-->` scene (8 lines): `<scene sceneID="TYy-pe-r3R">` containing `<controllerPlaceholder storyboardName="Preferences" id="W7f-Zh-TfF">` | Eliminated `"Preferences" is unreachable` build warning; the scene had no connections from any other scene (see D5.1) |
| `CLAUDE.md` | Updated `Preferences/` architecture line: "Preference pane ViewControllers" → "Preference pane SwiftUI views; `PreferenceWindowController` creates the window programmatically via `NSHostingController`" | Reflects post-migration architecture (see D5.2) |
| `docs/implementation/preferences-swiftui-migration.md` | Added corrective blockquote note to Phase 6 review `onChange` observation (line 392) pointing to modernization follow-up | Flags that deprecated forms were eliminated in modernization follow-up Phase 3 (see D5.5) |
| `docs/implementation/preferences-swiftui-modernization-followup.md` | Phase 5 status, checklist, decisions (D5.1–D5.5), verification log, resume instructions | State doc update |

## Verification log

### Phase 0

**2026-05-23 — Audit commands run by Phase 0 subagent:**

```
git log --oneline -5
```
Result: `e9e1398b feat(prefs): migrate preferences to SwiftUI` is HEAD. Prior commits unrelated to this follow-up pass.

```
git show --stat e9e1398b
```
Result: 27 files changed, 2592 insertions(+), 18489 deletions(-). Confirmed migration commit is `e9e1398b`.

```
grep -n MACOSX_DEPLOYMENT_TARGET Lirico.xcodeproj/project.pbxproj
```
Result:
- Line 899: `10.11` — SwiftLint aggregate target (Debug)
- Line 958: `10.11` — SwiftLint aggregate target (Release)
- Line 989: `11.0` — Lirico Debug
- Line 1015: `11.0` — Lirico Release
- Line 1036: `11.0` — LiricoHelper Debug
- Line 1057: `11.0` — LiricoHelper Release

```
grep -RnE 'if #available\(macOS|@available\(macOS' Lirico/Preferences/
```
Result: 1 hit — `LabPreferencesView.swift:150` — `if #available(macOS 12, *)` guarding `TextField.onSubmit`.

```
grep -RnE '\.onChange\(of:' Lirico/Preferences/
```
Result: 13 hits total:
- `GeneralPreferencesView.swift`: 7 sites (lines 76, 81, 108, 157, 180, 197, ~208)
- `DisplayPreferencesView.swift`: 6 sites (lines 211, 216, 221, 226, 252, 257)
- `SourcePreferencesView.swift`: 1 site (line 25)
All use deprecated single-argument closure form (`{ newValue in }` or `{ _ in }`).

```
grep -Rn 'macOS 1[12]' Lirico/Preferences/ Lirico/Component/ Lirico/Utility/
```
Result:
- `LabPreferencesView.swift:11` — comment about macOS 11–12 dismissal unreliability
- `LabPreferencesView.swift:46` — comment about SwiftUI sheet on macOS 11–12
- `LabPreferencesView.swift:150` — `#available(macOS 12, *)` guard for `onSubmit`
- `SourcePreferencesView.swift:45` — comment about drag handles on macOS 11–12
- `AppDelegate.swift:176` — `if #available(macOS 11, *)` (unrelated to Preferences, not in scope)

```
python3 -c "import json; ..." (Localizable.xcstrings junk key inspection)
```
Result:
- TOTAL: 68 string keys
- SUSPICIOUS: `['', '.*', '%lld']` — 3 junk keys, all with zero localizations
- `EMPTY_KEY_PRESENT: True`

Additional inspection: `'Lab'` and `'Vox'` are short but legitimate; `'OK'` has translations across 17 locales (legitimate).

```
python3 -m json.tool "Lirico/Supporting Files/Localizable.xcstrings" >/dev/null
```
Not run explicitly; string catalog confirmed valid JSON by python3 json.load succeeding.

```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | tail -30
```
Result: `** BUILD SUCCEEDED **` (exit code 0). No errors. Notes about unconditional run-script phases (Copy "Launch at Login Helper", Bump Build, Update Build Time) are pre-existing and unrelated to this work.

**Bug confirmations:**

1. `lyricsWindowFont` fallback bug — **CONFIRMED** at `Lirico/Utility/Extension.swift` line 94:
   ```swift
   ?? NSFont.labelFont(ofSize: CGFloat(defaults[.desktopLyricsFontSize]))
   ```
   Should be `defaults[.lyricsWindowFontSize]`. Pre-existing bug, not introduced by migration.

2. `ShortcutSearchLyrics` MAS review hiding — **CONFIRMED MISSING** in `ShortcutPreferencesView.swift`. No `IS_FOR_MAS` or `isInMASReview` check anywhere in the file. Old behavior defined in `IBInspection.swift` lines 33–43: when `IS_FOR_MAS` build flag is set and `defaults[.isInMASReview] != false`, call `removeFromSuperview()`. SwiftUI equivalent must hide the entire row.

3. `docs/implementation/preferences-swiftui-migration.md` Phase 0 review checkbox — **CONFIRMED UNCHECKED** at line 9: `- [ ] Phase 0 review`. Migration is otherwise complete (Phase 7 done).

**Unexpected finding — `appleLanguages` key casing:**
`UserDefaultsKeys.swift` line 99 defines `Key<[String]>("AppleLanguages")` — note capital `A`. However, the system `AppleLanguages` preference used by `NSLocale` / `NSBundle` is typically `"AppleLanguages"` (capital A). This appears correct. `GeneralPreferencesView.swift` uses `defaults.remove(.appleLanguages)` and `defaults[.appleLanguages] = [lan]` — consistent with the key definition. No issue.

**Unexpected finding — SwiftLint target deployment target:**
Lines 899 and 958 in `project.pbxproj` show `MACOSX_DEPLOYMENT_TARGET = 10.11` for the SwiftLint aggregate target. This is an aggregate target (no compiled code) so it has no practical effect, but Phase 1 should confirm whether to update it or leave it alone. Recommend leaving it unless it causes build warnings.

### Phase 0 review

**2026-05-23 — Independent verification by Phase 0 review subagent:**

Commands run and results:

```
git status --short
```
Result: `?? docs/implementation/preferences-swiftui-modernization-followup.md` — clean except for the new state doc. Consistent with state doc claim.

```
git log --oneline -5
```
Result: HEAD is `e9e1398b feat(prefs): migrate preferences to SwiftUI`. Consistent with state doc.

```
grep -RnE '\.onChange\(of:' Lirico/Preferences/ | wc -l
```
Result: **13 total** — consistent with state doc claim of 13.

Per-file breakdown verified:
- `GeneralPreferencesView.swift`: **6** (lines 76, 81, 108, 157, 180, 197) — state doc claimed 7 with "one more at ~208". Reading lines 190–215 confirms there is no 7th onChange in GeneralPreferencesView.swift. **Patched count from 7 to 6** in Phase 3 table.
- `DisplayPreferencesView.swift`: 6 (lines 211, 216, 221, 226, 252, 257) — consistent.
- `SourcePreferencesView.swift`: 1 (line 25) — consistent.

```
grep -RnE 'if #available\(macOS|@available\(macOS' Lirico/Preferences/
```
Result: 1 hit — `LabPreferencesView.swift:150` — consistent with state doc.

```
grep -RnE 'macOS 1[12]' Lirico/Preferences/ Lirico/Component/ Lirico/Utility/
```
Results: `LabPreferencesView.swift` lines 11, 46, 150; `SourcePreferencesView.swift` line 45; `AppDelegate.swift:176` (macOS 11, out of scope). Consistent with state doc.

```
grep -n MACOSX_DEPLOYMENT_TARGET Lirico.xcodeproj/project.pbxproj
```
Result: Lines 899/958 = 10.11 (SwiftLint aggregate), lines 989/1015/1036/1057 = 11.0 (Lirico + LiricoHelper Debug + Release). Consistent with state doc.

```
python3 -c "import json; d=json.load(…); …"
```
Result: total=68, has_empty=True, has_dotstar=True, has_lld=True. Consistent with state doc.

**Bug confirmations (independent re-verification):**

1. `lyricsWindowFont` fallback bug — **CONFIRMED** at `Lirico/Utility/Extension.swift` line 94: `?? NSFont.labelFont(ofSize: CGFloat(defaults[.desktopLyricsFontSize]))`. Should be `defaults[.lyricsWindowFontSize]`. Consistent with state doc.

2. `ShortcutSearchLyrics` MAS review hiding — **CONFIRMED MISSING**. Full read of `ShortcutPreferencesView.swift` confirms no `IS_FOR_MAS`, `isInMASReview`, or conditional hiding at the `ShortcutSearchLyrics` row. `IBInspection.swift` lines 33–43 define `isRemovedDuringMASReview` as `#if IS_FOR_MAS` + `defaults[.isInMASReview] != false` + `removeFromSuperview()`. State doc describes this accurately.

3. `docs/implementation/preferences-swiftui-migration.md` Phase 0 review — **CONFIRMED UNCHECKED** at line 9. State doc describes this correctly.

**State doc structure check:** All 8 required sections present (Current status, Phase checklist, Current migration diff summary, Decisions, Unknowns resolved autonomously, Phase 1–5 proposed file list, Changed files by phase, Verification log, Resume instructions). Phase 1–5 proposed file lists are concrete and per-file rationale is provided. Resume instructions are actionable.

**Patches applied by this review:**
- `Current status` block: updated "Current phase" to "Phase 1 (pending)", "Last completed phase" to "Phase 0 review — verified 2026-05-23".
- Phase checklist: marked `Phase 0` and `Phase 0 review` as `[x]`.
- Phase 3 table: corrected `GeneralPreferencesView.swift` `onChange` count from 7 to 6, removed the spurious "one more at ~208" note.

**Overall verdict: PASS-WITH-PATCHES. Green light for Phase 1.**

### Phase 1

**2026-05-23 — Phase 1 implementation subagent:**

**Dependency platform check:**

Checked DerivedData checkouts (pinned commits from `Package.resolved`):
- LyricsKit (`44588c2c`, v1.8.0): `platforms: [.macOS(.v11)]`
- MusicPlayer (`f220ac6c`, v1.8.0): `platforms: [.macOS(.v10_15), .iOS(.v13)]`

Both dependencies declare minimums well below macOS 15. Bump to 15 is safe. (See D1.1.)

**BEFORE counts:**
```
grep -c 'MACOSX_DEPLOYMENT_TARGET = 11.0' project.pbxproj  → 4
grep -c 'MACOSX_DEPLOYMENT_TARGET = 10.11' project.pbxproj → 2
```

**Edits made:**
- `project.pbxproj`: 6 `MACOSX_DEPLOYMENT_TARGET` entries changed to `15.0` (4× from `11.0`, 2× from `10.11`)
- `LiricoPackage/Package.swift`: `.macOS(.v11)` → `.macOS(.v15)`
- `CLAUDE.md`: `macOS 11+ only` → `macOS 15+ only`
- `README.md`: `macOS 11+` → `macOS 15+`

**AFTER counts:**
```
grep -c 'MACOSX_DEPLOYMENT_TARGET = 15.0' project.pbxproj  → 6
grep -c 'MACOSX_DEPLOYMENT_TARGET = 11.0' project.pbxproj  → 0
grep -c 'MACOSX_DEPLOYMENT_TARGET = 10.11' project.pbxproj → 0
```

**plutil lint:**
```
plutil -lint Lirico.xcodeproj/project.pbxproj
→ Lirico.xcodeproj/project.pbxproj: OK
```

**Sanity sweep — remaining macOS 11 references:**
- `docs/prompt.md` lines 23, 61, 183, 185, 212: historical migration prompt — left unchanged (pre-existing, not current state claims)
- `docs/implementation/preferences-swiftui-migration.md` multiple lines: historical migration decisions — left unchanged (rationale context for compatibility branches removed in Phase 3)
- No hits in `README.md` or `CLAUDE.md`

**Build result:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | tee /tmp/lyricsx-phase1-build.log
→ ** BUILD SUCCEEDED **
```

Warnings present (all pre-existing, none introduced by Phase 1):
- 13× `onChange(of:perform:)` deprecated in macOS 14 (Phase 3 cleanup target)
- 2× `SMLoginItemSetEnabled` deprecated in macOS 13
- `appStoreReceiptURL` deprecated in macOS 15
- `init(contentsOf:)` deprecated in macOS 15 (in `DragNDropView.swift`)
- Various macOS 10.14 deprecations unrelated to Preferences
- Storyboard `Main.storyboard` SF Symbol deprecation
- Storyboard `Main.storyboard` unreachable `Preferences` controller (stale reference — this is the deleted Preferences storyboard no longer connected; Phase 5 will flag it)

No errors. No new warnings introduced by Phase 1.

### Phase 2

**2026-05-23 — Phase 2 implementation subagent:**

**IS_FOR_MAS flag investigation:**
```
grep -n 'SWIFT_ACTIVE_COMPILATION_CONDITIONS\|GCC_PREPROCESSOR_DEFINITIONS' Lirico.xcodeproj/project.pbxproj
find . -name '*.xcconfig' -exec grep -In 'IS_FOR_MAS' {} \;
```
Result: `SWIFT_ACTIVE_COMPILATION_CONDITIONS = ""` at project Debug level; `""` at project Release level (via OTHER_SWIFT_FLAGS). No `.xcconfig` files in the repository. `IS_FOR_MAS` is not defined in any build configuration. The flag only exists as `#if IS_FOR_MAS` in `IBInspection.swift` (3 occurrences). See D2.3.

**Edits made:**
1. `ShortcutPreferencesView.swift`: Added `#if IS_FOR_MAS` / `if defaults[.isInMASReview] != false` conditional around the "Search lyrics" row in `lyricsActionsSection`. Exact match to IBInspection.swift `isRemovedDuringMASReview` semantics.
2. `Extension.swift` line 94: `defaults[.desktopLyricsFontSize]` → `defaults[.lyricsWindowFontSize]` in `lyricsWindowFont` fallback.
3. `preferences-swiftui-migration.md` line 9: Added corrective blockquote note below `[ ] Phase 0 review`.

**Build result:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | tee /tmp/lyricsx-phase2-build.log | tail -30
→ ** BUILD SUCCEEDED **
```

**Error/warning scan:**
```
grep -cE '\berror:' /tmp/lyricsx-phase2-build.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase2-build.log → 2 (incremental build; only changed files recompiled)
```
0 errors. Warning count is 2 in this incremental build (only `ShortcutPreferencesView.swift` and `Extension.swift` recompiled); full-rebuild baseline from Phase 1 was 13 onChange deprecations — these remain unchanged and will be resolved in Phase 3.

**MAS condition sanity grep:**
```
grep -n 'IS_FOR_MAS\|isInMASReview' Lirico/Preferences/ShortcutPreferencesView.swift Lirico/Utility/IBInspection.swift
```
Result:
- `ShortcutPreferencesView.swift:54`: `#if IS_FOR_MAS`
- `ShortcutPreferencesView.swift:55`: `if defaults[.isInMASReview] != false {`
- `IBInspection.swift:10`: `#if IS_FOR_MAS`
- `IBInspection.swift:22`: `#if IS_FOR_MAS`
- `IBInspection.swift:23`: `if newValue, defaults[.isInMASReview] != false {`
- `IBInspection.swift:36`: `#if IS_FOR_MAS`
- `IBInspection.swift:37`: `if newValue, defaults[.isInMASReview] != false {`

Condition matches. `newValue` was always `true` (storyboard set `isRemovedDuringMASReview = true`), so the SwiftUI conditional omits that term.

**Font fix sanity grep:**
```
grep -n 'lyricsWindowFontSize\|desktopLyricsFontSize' Lirico/Utility/Extension.swift
```
Result:
- Line 83: `desktopLyricsFont` uses `desktopLyricsFontSize` (x2) — correct, unchanged
- Line 92: `lyricsWindowFont` uses `lyricsWindowFontSize` for primary size — correct
- Line 94: `lyricsWindowFont` fallback now uses `lyricsWindowFontSize` — **fixed**

### Phase 1 review

**2026-05-23 — Independent verification by Phase 1 review subagent:**

**Commands run and results:**

```
git status --short
```
Result: `M CLAUDE.md`, `M Lirico.xcodeproj/project.pbxproj`, `M LiricoPackage/Package.swift`, `M README.md`, `?? docs/implementation/preferences-swiftui-modernization-followup.md`. No Lirico/* source files modified. Consistent with state doc claim.

```
git diff --stat
```
Result: 4 files changed, 3 insertions(+), 3 deletions(-). Binary delta on project.pbxproj (72816 → 72814 bytes, 6 target strings replaced). Consistent with a clean 6-entry deployment-target bump only.

```
grep -n MACOSX_DEPLOYMENT_TARGET Lirico.xcodeproj/project.pbxproj
```
Result: **6 entries, all at `15.0`** (lines 899, 958, 989, 1015, 1036, 1057). Zero entries at `11.0` or `10.11`. Consistent with state doc AFTER counts.

```
cat LiricoPackage/Package.swift
```
Result: `platforms: [.macOS(.v15)]` at line 57. No `.v11` / `.v10_15` remaining. Consistent with state doc.

```
grep -n 'macOS 11' README.md CLAUDE.md
```
Result: zero hits. Both documents now say macOS 15+. No stale minimum-version claim remaining.

**Platform statement natural-language check:**
- `CLAUDE.md` line 9: `- **Platform**: macOS 15+ only` — correct, reads naturally.
- `README.md` line 30: `- macOS 15+` in Requirements section — correct.

```
plutil -lint Lirico.xcodeproj/project.pbxproj
```
Result: `Lirico.xcodeproj/project.pbxproj: OK`

```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | tee /tmp/lyricsx-phase1-review-build.log | tail -40
```
Result: `** BUILD SUCCEEDED **`

```
grep -cE '\bwarning:' /tmp/lyricsx-phase1-review-build.log
grep -cE '\berror:' /tmp/lyricsx-phase1-review-build.log
```
Result: **0 warnings, 0 errors** (incremental build; only 1 xcodebuild destination-selection advisory, not a code warning). No new SDK availability warnings introduced by the deployment target bump.

**Dependency platform sanity check:**

Inspected DerivedData checkouts against `Package.resolved` pinned commits:
- LyricsKit (revision `44588c2c`, v1.8.0): `platforms: [.macOS(.v11)]` — well below 15; bump is safe.
- MusicPlayer (revision `f220ac6c`, v1.8.0): `platforms: [.macOS(.v10_15), .iOS(.v13)]` — well below 15; bump is safe.

Both match the commits recorded in state doc D1.1 exactly.

**State doc consistency check:** All required sections present. `## Current status` updated to Phase 1 review complete, Phase 2 pending. `## Phase checklist` Phase 1 and Phase 1 review both `[x]`. `## Decisions` has D1.1, D1.2, D1.3 entries. `## Changed files by phase` has Phase 1 subsection with all 5 changed files. `## Verification log` has Phase 0, Phase 0 review, and Phase 1 entries. `## Resume instructions` present.

**Patches applied by this review:**
- `## Current status`: updated "Current phase" to "Phase 2 (pending)", "Last completed phase" to "Phase 1 review — verified 2026-05-23", "Build status" to Phase 1 review build.
- `## Phase checklist`: marked `Phase 1 review` as `[x]`.
- `## Resume instructions`: updated to reflect Phase 1 review completion and Phase 2 as next step.

**Overall verdict: PASS. Green light for Phase 2.**

### Phase 3

**2026-05-23 — Phase 3 implementation subagent:**

**Scope of changes:**
- `GeneralPreferencesView.swift`: 6 onChange sites updated to two-arg form `{ _, newValue in ... }`
- `DisplayPreferencesView.swift`: 6 onChange sites updated to zero-arg form `{ vm.save...() }`
- `SourcePreferencesView.swift`: 1 onChange site updated to two-arg form; macOS 11–12 drag-handles comment removed
- `LabPreferencesView.swift`: `if #available(macOS 12, *)` guard removed (`.onSubmit` kept unconditionally); 2 stale macOS 11–12 comments removed from doc comment and inline comment

**Fresh grep results:**
```
grep -RnE 'macOS 1[1234]|if #available' Lirico/Preferences/
→ (no output)

grep -RnE '\.onChange\(of:' Lirico/Preferences/ | grep -v '_, '
→ (no output — all calls use modern form)
```

**Incremental build (after edits):**
```
grep -cE '\berror:' /tmp/lyricsx-phase3-build.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase3-build.log → 20
grep -cE "onChange.*deprecated" /tmp/lyricsx-phase3-build.log → 0
```

**Final clean build:**
```
xcodebuild clean build → ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase3-final.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase3-final.log → 31
grep -E "warning:.*onChange" /tmp/lyricsx-phase3-final.log → (no output)
```

Remaining 31 warnings breakdown (all pre-existing, none in Preferences files, all out of scope):
- 11× `FrameworkToolboxMacros` missing dependency warnings (SPM macro dep graph, dependency's issue)
- 2× `SMLoginItemSetEnabled` deprecated in macOS 13 (GeneralPreferencesView — pre-existing, Phase 3 did not introduce)
- 2× `appStoreReceiptURL` deprecated in macOS 15 (AppEnvironment.swift)
- 2× DFRPrivate umbrella header (TouchBarHelper dependency)
- 1× `init(contentsOf:)` deprecated in macOS 15 (DragNDropView.swift)
- 2× `filePromise` deprecated in macOS 10.14 (SearchLyricsViewController.swift)
- 1× `keyedUnarchiveFromDataTransformerName` deprecated in macOS 10.14 (Observation.swift)
- 2× appintentsmetadataprocessor advisory (not code warnings)
- 1× Main.storyboard "Preferences" unreachable (Phase 5 scope)
- 1× Main.storyboard SF Symbol deprecated
- baseline: 13 onChange deprecations → **0 after Phase 3** (all eliminated)

**IS_FOR_MAS build:**
```
SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS' → ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase3-mas.log → 0
```

ShortcutPreferencesView.swift not touched in Phase 3. Phase 2 MAS block unaffected.

**BEFORE/AFTER onChange deprecation warnings:**
- Phase 1 baseline: 13 onChange deprecation warnings
- After Phase 3: 0 onChange deprecation warnings in Preferences

### Phase 5

**2026-05-23 — Phase 5 implementation subagent:**

**Goal 1 — Stale references to deleted Preferences storyboard/classes:**

```
for cls in AlphaColorWell FilterKey PreferenceDisplayViewController ... FontSelectTextField; do
    grep -RInE "\b$cls\b" Lirico/ LiricoHelper/ LiricoPackage/
done
```
Result: **0 hits for all 10 deleted class names.** No stale Swift references.

```
grep -RInE 'Preferences\.storyboard|Preferences\.xcstrings|mul\.lproj' Lirico/ LiricoHelper/ LiricoPackage/ Lirico.xcodeproj/
```
Result: 1 hit — `project.pbxproj:221` for `mul.lproj/Main.xcstrings` (the app's main storyboard string catalog, not Preferences). No Preferences storyboard/xcstrings refs.

```
grep -n 'Preferences' Lirico/Base.lproj/Main.storyboard
```
Result: 3 hits — line 357 (menu item "Preferences..." — legitimate), line 462 `<!--Preferences-->` comment, line 465 `<controllerPlaceholder storyboardName="Preferences" id="W7f-Zh-TfF">` — **stale reference confirmed.**

```
grep -n 'W7f-Zh-TfF\|TYy-pe-r3R' Lirico/Base.lproj/Main.storyboard
```
Result: only lines 463 and 465 themselves — **no external connections to this scene.** Safe to remove.

**Edit applied:** Removed the entire `<!--Preferences-->` scene block (lines 462–469 of original file) from `Main.storyboard`. This eliminates the `"Preferences" is unreachable` build warning.

```
for f in AlphaColorWell.swift FilterKey.swift ... Preferences.storyboard; do
    grep -c "$f" project.pbxproj
done
```
Result: **0 for all files.** pbxproj is clean.

**Goal 2 — Stale macOS 11/12 compatibility code:**

```
grep -RnIE 'macOS 1[12]([^4-9]|$)' Lirico/ LiricoHelper/ LiricoPackage/
```
Result: 1 hit — `AppDelegate.swift:176`: `if #available(macOS 11, *)` — out of Preferences scope. Logged as D5.3 (deferred).

```
grep -RnIE 'if #available\(macOS 1[1-4]' Lirico/ LiricoHelper/ LiricoPackage/
grep -RnIE '@available\(macOS 1[1-4]' Lirico/ LiricoHelper/ LiricoPackage/
```
Result: Same 1 hit — `AppDelegate.swift:176`. No Preferences files have any remaining macOS 11/12/13/14 availability guards. Phase 3 successfully removed all Preferences-related guards.

**Goal 3 — Doc reconciliation:**

- `docs/implementation/preferences-swiftui-migration.md`: Added corrective note to Phase 6 review `onChange` observation (line 392). All other historical `macOS 11` references in decisions/rationale sections left unchanged per D1.3.
- `CLAUDE.md`: Updated `Preferences/` line from "ViewControllers" to "SwiftUI views" (see D5.2).

**Goal 4 — Final build + checks:**

```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug clean build
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase5-build.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase5-build.log → 30
grep -nE "Preferences.*unreachable|storyboard.*Preferences" /tmp/lyricsx-phase5-build.log → (no output — warning eliminated)
```
Warning count dropped from 31 (Phase 4 baseline) to **30** — the "Preferences unreachable" storyboard warning was eliminated by removing the stale scene.

```
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS'
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase5-mas.log → 0
```

```
git diff --check → (no output — no whitespace issues)
plutil -lint Lirico.xcodeproj/project.pbxproj → OK
python3 -m json.tool 'Lirico/Supporting Files/Localizable.xcstrings' >/dev/null → XCSTRINGS_OK
```

**onChange non-Preferences final check:**
```
grep -RnIE '\.onChange\(of:' Lirico/ LiricoHelper/ | grep -v 'Preferences/'
```
Result: **0 hits outside Preferences.** No non-Preferences deprecated onChange sites exist.

### Phase 5 review

**2026-05-23 — Independent verification by Phase 5 review subagent:**

**git status scope check:**
```
git status --short
```
Result:
```
 M CLAUDE.md
 M Lirico.xcodeproj/project.pbxproj
 M Lirico/Base.lproj/Main.storyboard
 M Lirico/Preferences/DisplayPreferencesView.swift
 M Lirico/Preferences/GeneralPreferencesView.swift
 M Lirico/Preferences/LabPreferencesView.swift
 M Lirico/Preferences/ShortcutPreferencesView.swift
 M Lirico/Preferences/SourcePreferencesView.swift
 M "Lirico/Supporting Files/Localizable.xcstrings"
 M Lirico/Utility/Extension.swift
 M LiricoPackage/Package.swift
 M README.md
 M docs/implementation/preferences-swiftui-migration.md
?? docs/implementation/preferences-swiftui-modernization-followup.md
```
Scope is fully contained. Sanity-checks:
- All Phase 1–5 expected modified files are present.
- Phase 3 Preferences views: all 5 present (General, Display, Lab, Shortcut, Source).
- Phase 5 files: `Main.storyboard` and `CLAUDE.md` are present.
- Only untracked file is the state doc itself — correct (no commit).
- No surprises: no DerivedData, no .DS_Store, no random Swift files.
- `Lirico/Component/LyricsSelector.swift` and `Lirico/Component/PersistenceSettings.swift` from the migration are NOT in the modified set — correct, they were modified by the migration commit (now committed), not by this follow-up pass.

**Stale-reference sweep — deleted class names (expect 0 each):**
```
for cls in AlphaColorWell FilterKey PreferenceDisplayViewController PreferenceFilterViewController
         PreferenceGeneralViewController PreferenceLabViewController PreferenceShortcutViewController
         PreferenceSourceViewController PreferenceViewController FontSelectTextField; do
    hits=$(grep -RInE "\b$cls\b" Lirico/ LiricoHelper/ LiricoPackage/ 2>/dev/null | wc -l)
    echo "$cls -> $hits"
done
```
Result: **0 for all 10 deleted class names.** No stale Swift references anywhere.

**Stale storyboard/xcstrings/mul.lproj references:**
```
grep -RInE 'Preferences\.storyboard|Preferences\.xcstrings|mul\.lproj' \
    Lirico/ LiricoHelper/ LiricoPackage/ Lirico.xcodeproj/ 2>/dev/null
```
Result: 1 hit — `project.pbxproj:221: mul.lproj/Main.xcstrings` — this is the `Main.xcstrings` string catalog for `Main.storyboard`, not a Preferences file. Expected and legitimate.

**Main.storyboard scene removal verification:**
```
grep -n 'Preferences\|TYy-pe-r3R\|W7f-Zh-TfF' Lirico/Base.lproj/Main.storyboard
```
Result:
- Line 357: `<menuItem title="Preferences..." ...>` — menu item title, legitimate.
- Line 359: `<action selector="showPreferences:" .../>` — menu action, legitimate.
- **0 hits for `TYy-pe-r3R`, `W7f-Zh-TfF`** — stale scene and controller placeholder fully removed.
- **0 hits for `controllerPlaceholder storyboardName="Preferences"`** — confirmed gone.

**Main.storyboard XML validity:**
```
xmllint --noout Lirico/Base.lproj/Main.storyboard 2>&1
```
Result: **(no output — XML is valid)**

**macOS 11/12 full sweep (expect only AppDelegate.swift:176):**
```
grep -RnIE 'macOS 1[12]([^4-9]|$)' Lirico/ LiricoHelper/ LiricoPackage/ 2>/dev/null
grep -RnIE 'if #available\(macOS 1[1-4]' Lirico/ LiricoHelper/ LiricoPackage/ 2>/dev/null
grep -RnIE '@available\(macOS 1[1-4]' Lirico/ LiricoHelper/ LiricoPackage/ 2>/dev/null
```
Result: **1 hit only** — `AppDelegate.swift:176: if #available(macOS 11, *)` — logged as D5.3 (deferred cleanup). No Preferences files have any remaining macOS 11/12/13/14 availability guards. Zero `@available` hits. All expected.

Note: `AppDelegate.swift` also contains `if #available(OSX 10.13, *)` at line 109 — this did not appear in the `macOS 1[1-4]` grep because it uses the `OSX` form (not `macOS`) and `.v10_13` is below the sweep range. It is out of Preferences scope and pre-existing.

**Deployment target consistency:**
```
grep -n MACOSX_DEPLOYMENT_TARGET Lirico.xcodeproj/project.pbxproj
```
Result: **6 entries, all `15.0`** (lines 899, 958, 989, 1015, 1036, 1057). No `11.0` or `10.11` remaining.

```
grep -n 'macOS' LiricoPackage/Package.swift
```
Result: `platforms: [.macOS(.v15)]` — correct.

```
grep -n 'macOS' README.md CLAUDE.md
```
Result: `README.md:30: - macOS 15+`, `CLAUDE.md:9: - **Platform**: macOS 15+ only`. Both consistent. No stale `macOS 11` claims in any of the three files.

**String catalog:**
```
python3 -m json.tool 'Lirico/Supporting Files/Localizable.xcstrings' >/dev/null
```
Result: **XCSTRINGS_OK**

```
python3 -c "import json; d=json.load(open('Lirico/Supporting Files/Localizable.xcstrings')); \
    s=d['strings']; print('total:', len(s)); print('junk:', any(k in s for k in ('', '.*', '%lld')))"
```
Result: `total: 65`, `junk: False`. Correct.

**CLAUDE.md architecture line:**
`CLAUDE.md` line 65: `- **Preferences/** — Preference pane SwiftUI views (General, Display, Filter, Shortcut, Source, Lab); PreferenceWindowController creates the window programmatically via NSHostingController`. Accurately reflects post-migration architecture. SwiftUI views are named, the programmatic window creation is mentioned. No ViewController language remains. Verdict: accurate and readable to a future agent.

**Migration doc corrective notes:**
1. Phase 0 corrective note — `docs/implementation/preferences-swiftui-migration.md` line 14–15: `[ ] Phase 0 review` with blockquote `> Phase 0 review was deferred at migration time and is being completed by the modernization follow-up; see docs/implementation/preferences-swiftui-modernization-followup.md.` Correct and points to the right file.
2. Phase 6 onChange corrective note — line 393: `> **Corrective note (modernization follow-up, 2026-05-23):** The deprecated single-argument onChange(of:) forms were eliminated in Phase 3 of the modernization follow-up, and the deployment target was raised to macOS 15+. See docs/implementation/preferences-swiftui-modernization-followup.md.` Correct and points to the right file.

**Full clean build — default Debug:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug clean build 2>&1 | tee /tmp/lyricsx-phase5-review.log
```
Result: `** BUILD SUCCEEDED **`
- Error count: **0**
- Warning count: **30**
- `unreachable` warnings: **0** (Preferences stale scene eliminated by Phase 5)
- `onChange` deprecation warnings: **0** (all eliminated in Phase 3)
- Preferences-path warnings: 2 (`SMLoginItemSetEnabled` deprecated macOS 13 in `GeneralPreferencesView.swift` lines 77, 85 — pre-existing, out of scope)

Warning sample (5 representative out-of-scope warnings):
1. 11× `FrameworkToolboxMacros` missing dependency (SPM macro dep graph — upstream dep issue)
2. 2× DFRPrivate umbrella header (TouchBarHelper dep — upstream dep issue)
3. 2× `appStoreReceiptURL` deprecated macOS 15 (AppEnvironment.swift — pre-existing, separate scope)
4. 1× `init(contentsOf:)` deprecated macOS 15 (DragNDropView.swift — pre-existing, separate scope)
5. 2× `SMLoginItemSetEnabled` deprecated macOS 13 (GeneralPreferencesView.swift — pre-existing, separate scope)

**IS_FOR_MAS build:**
```
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS'
→ ** BUILD SUCCEEDED **
```
Error count: **0**. MAS compilation conditions compile correctly. `ShortcutPreferencesView.swift #if IS_FOR_MAS` branch is valid SwiftUI.

**Other integrity checks:**
```
git diff --check → (no output — no whitespace issues)
plutil -lint Lirico.xcodeproj/project.pbxproj → OK
```

**State doc audit:**
- `## Current status`: updated by this review — phase COMPLETE, build PASS.
- `## Phase checklist`: all phases 0–5 impl and review `[x]`.
- `## Decisions`: D1.1–D1.3, D2.1–D2.3, D3.1–D3.3, D4.1–D4.2, D5.1–D5.5 — covers all non-obvious decisions. Every required decision entry is present (upstream dep compat, SwiftLint bump, MAS condition, migration doc note, onChange form choices, Coordinator kept, Up/Down buttons kept, junk key removal, deferred translation salvage, storyboard scene removal, CLAUDE.md update, AppDelegate.swift:176 deferred, non-Preferences onChange).
- `## Unknowns resolved autonomously`: U4.1 present. D2.3 cross-referenced.
- `## Changed files by phase`: all phases have subsections with per-file rationale.
- `## Verification log`: entries for Phase 0, Phase 0 review, Phase 1, Phase 1 review, Phase 2, Phase 2 review, Phase 3, Phase 3 review, Phase 4, Phase 4 review, Phase 5, Phase 5 review (this entry).
- `## Resume instructions`: updated below.

**Patches applied by this review:**
- `## Current status`: updated "Current phase" to "COMPLETE", "Last completed phase" to "Phase 5 review — verified 2026-05-23", "Build status" updated, "Known blockers" updated.
- `## Phase checklist`: marked `Phase 5 review` as `[x]`.
- `## Verification log`: added this Phase 5 review entry.
- `## Resume instructions`: updated.

**Overall verdict: PASS. Follow-up complete.**

### Phase 4

**2026-05-23 — Phase 4 implementation subagent:**

**Background investigation:**

```
python3 (Localizable.xcstrings inspection)
```
Result: TOTAL: 68, VERSION: 1.0, SRC_LANG: en. Suspicious keys `''`, `'.*'`, `'%lld'` all present. All three entries are empty `{}` objects — no `localizations` dict, no `extractionState`, no `comment`. Pure extraction artifacts.

**Source-code reference check:**
```
grep -RIn '"\\.*"' Lirico/ LiricoHelper/ LiricoPackage/  → no Swift hits
grep -RIn '"%lld"' Lirico/ LiricoHelper/ LiricoPackage/  → hit only in xcstrings file itself
grep -RIn 'String(localized: "")' Lirico/ LiricoHelper/ LiricoPackage/  → 0 hits
grep -RIn 'Text("")\|Text("\\.*")\|Text("%lld")' Lirico/ ...  → 0 hits
grep -RIn '\\.*' Lirico/Preferences/  → FilterPreferencesView.swift:88: Text(".*")
```
`Text(".*")` at line 88 is a regex-badge visual indicator — a fixed technical symbol, not a linguistically translatable string. Key safe to remove per D4.1.

**Deleted file recovery check:**
```
git log --diff-filter=D --format='%H %s' -- 'Lirico/mul.lproj/Preferences.xcstrings'
```
Result: `e9e1398bada999be8280bb0e67f50b16d53fa27f feat(prefs): migrate preferences to SwiftUI`

```
git show e9e1398b~1:'Lirico/mul.lproj/Preferences.xcstrings' | python3 (language extraction)
```
Result: 18 locales: `['ar', 'base', 'de', 'en', 'es', 'fa', 'fr', 'id', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'ru', 'uk', 'zh-Hans', 'zh-Hant']`

**Formatting check (before edit):**
- Indent: 2-space (confirmed via `head -c 500`)
- Trailing newline: present (confirmed via `tail -c 200`)

**Edit performed (Python script):**
```
BEFORE TOTAL: 68
REMOVED: ['', '.*', '%lld']
NEW TOTAL: 65
```
No SKIP fires — all three keys had empty entries with no translations.

**Post-edit verification:**
```
python3 -m json.tool Localizable.xcstrings >/dev/null → JSON OK
python3 -c ... → TOTAL: 65, emptyKey: False, dotstar: False, lld: False
```
BEFORE: 68 keys / AFTER: 65 keys / Removed: exactly 3 / No unexpected removals.

**Spot-check preserved translations:**
- `'Download'` → localizations in `['ar', 'de', 'en', 'es', 'fa', ...]`
- `'Font Fallback: %@'` → localizations in `['ar', 'de', 'en', 'es', 'fa', ...]`
- `'Lyrics Window'` → localizations in `['ar', 'de', 'en', 'es', 'fa', ...]`
- `'OK'` → localizations in `['ar', 'de', 'en', 'es', 'fa', ...]`
- `'Search Lyrics'` → localizations in `['ar', 'de', 'en', 'es', 'fa', ...]`
All non-Preferences translations survived intact.

**Build result:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug clean build
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase4-build.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase4-build.log → 31
```
0 errors. 31 warnings — identical to Phase 3 baseline. No new warnings or errors introduced by removing the 3 junk keys.

### Phase 4 review

**2026-05-23 — Independent verification by Phase 4 review subagent:**

**git status scope check:**
```
git status --short
```
Result: `M "Lirico/Supporting Files/Localizable.xcstrings"` present (Phase 4 modification). State doc (`?? docs/implementation/preferences-swiftui-modernization-followup.md`) is the only other new artifact. Phase 1/2/3 modified files (CLAUDE.md, project.pbxproj, Preferences views, Extension.swift, Package.swift, README.md, migration.md) remain modified — all expected from prior phases. No extra production files touched in Phase 4.

**JSON validity:**
```
python3 -m json.tool 'Lirico/Supporting Files/Localizable.xcstrings' >/dev/null
```
Result: **JSON_OK**

**Key count and junk-key absence:**
```
python3 (key count + presence checks)
```
Result:
- TOTAL: **65** — matches implementor's expected 68 → 65 (3 removed)
- VERSION: 1.0
- SRC_LANG: en
- `''` present? **False** — junk key absent
- `'.*'` present? **False** — junk key absent
- `'%lld'` present? **False** — junk key absent

All three claimed removals confirmed.

**Translation-preservation spot check (independent, seed=42):**
```
python3 (random.seed(42) sample of keys_with_translations)
```
Result: **7 keys have translations** in the catalog (all the rest are new SwiftUI-migration strings with no translations yet — consistent with D4.2). The 7 sampled keys all have 17 locales intact:
- `'Touch Bar lyrics is not supported in Mac App Store Version. Please download on GitHub.'` → 17 langs: ar, de, en, es, fa, fr, ...
- `'Download'` → 17 langs
- `'Unable to enable Touch Bar lyrics.'` → 17 langs
- `'Lyrics Window'` → 17 langs
- `'Search Lyrics'` → 17 langs
- `'OK'` → 17 langs
- `'Font Fallback: %@'` → 17 langs

No translation entry went empty. All 7 pre-existing translations are fully intact.

**`Text(".*")` visual badge confirmation:**
Read `FilterPreferencesView.swift` lines 83–95: `Text(".*")` appears at line 88 inside `keywordRow(index:)`, rendered in monospaced caption font with secondary foreground color, inside an `HStack` — only when `keywords[index].hasPrefix("/")`. This is a fixed regex-wildcard visual badge displayed as a monospaced label to signal a regex-type keyword. It is not linguistically translatable. Removing the xcstrings entry causes SwiftUI to fall back to the literal `".*"`, which is identical runtime behavior. Confirmed non-localizable display artifact.

**Deleted `Preferences.xcstrings` recoverability:**
```
git log --diff-filter=D --format='%H' -- Lirico/mul.lproj/Preferences.xcstrings
```
Result: deletion commit `e9e1398bada999be8280bb0e67f50b16d53fa27f`
```
git show e9e1398bada999be8280bb0e67f50b16d53fa27f~1:Lirico/mul.lproj/Preferences.xcstrings | python3 (locale extraction)
```
Result: **18 locales confirmed**: `['ar', 'base', 'de', 'en', 'es', 'fa', 'fr', 'id', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'ru', 'uk', 'zh-Hans', 'zh-Hant']` — matches implementor's D4.2 list exactly. File is recoverable.

**File formatting sanity:**
- `head -c 200`: Opens `{` with `"sourceLanguage": "en"`, `"strings": {` at 2-space indent — valid Xcode xcstrings format.
- `tail -c 200`: Ends with closing `}` braces in correct JSON structure.
- `wc -l`: 814 lines (down from ~817 before 3 junk key removals, each key was ~1–2 lines of `"key": {}` plus surrounding whitespace).
- Trailing newline: confirmed present (tail shows `}` then newline at end).
- No formatting corruption observed.

**Default Debug clean build:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug clean build
→ ** BUILD SUCCEEDED **
```
- Error count: **0**
- Warning count: **31** — exact Phase 3 parity. No string-catalog warnings. No localization warnings.

**IS_FOR_MAS build:**
```
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS'
→ ** BUILD SUCCEEDED **
```
0 errors. All pre-existing FrameworkToolboxMacros warnings only.

**State doc consistency:** All Phase 4 entries present: D4.1 (junk key removal), D4.2 (Preferences.xcstrings deferred salvage), U4.1 (Text(".*") decision), Changed files → Phase 4 subsection, Verification log → Phase 4 subsection with before/after counts.

**Patches applied by this review:**
- `## Current status`: updated "Current phase" to "Phase 5 (pending)", "Last completed phase" to "Phase 4 review — verified 2026-05-23", "Build status" updated to Phase 4 review build.
- `## Phase checklist`: marked `Phase 4 review` as `[x]`.
- `## Verification log`: added this Phase 4 review entry.
- `## Resume instructions`: updated below.

**Overall verdict: PASS. No defects found. Green light for Phase 5.**

---

### Phase 3 review

**2026-05-23 — Independent verification by Phase 3 review subagent:**

**git status check:**
```
git status --short
```
Result: Modified files include all four Phase 3 Preferences views (GeneralPreferencesView.swift, DisplayPreferencesView.swift, SourcePreferencesView.swift, LabPreferencesView.swift) plus Phase 1/2 files (CLAUDE.md, project.pbxproj, LiricoPackage/Package.swift, README.md, ShortcutPreferencesView.swift, Extension.swift, preferences-swiftui-migration.md). State doc is untracked `??`. No files outside `Lirico/Preferences/` and expected Phase 1/2 files were modified in Phase 3.

**Legacy single-arg onChange grep (expect 0 hits):**
```
grep -RnE '\.onChange\(of:[^)]+\)[[:space:]]*\{[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in' Lirico/Preferences/
```
Result: **0 hits**. No legacy single-argument closures remaining.

**Total onChange grep (expect 13 modern-form hits):**
```
grep -RnE '\.onChange\(of:' Lirico/Preferences/
```
Result: **13 hits** — 6 in GeneralPreferencesView.swift, 6 in DisplayPreferencesView.swift, 1 in SourcePreferencesView.swift. Zero in LabPreferencesView.swift (no onChange in that file).

**macOS availability grep (expect 0 hits):**
```
grep -RnE 'macOS 1[1234]|if #available\(macOS' Lirico/Preferences/
```
Result: **0 hits**. All compat guards and comments removed.

**Per-file onChange form validation:**

- `GeneralPreferencesView.swift` (6 sites): ALL two-arg `{ _, name in ... }` form. Bodies verified: each closure references its captured parameter (`enabled`, `idx`, `newIndex`). Semantically correct.
- `DisplayPreferencesView.swift` (6 sites): ALL zero-arg `{ vm.save...() }` form. Bodies verified: each closure calls a side-effect save method; no value capture needed. The original closures were `{ _ in vm.save...() }` (discarded). Semantically equivalent.
- `SourcePreferencesView.swift` (1 site): Two-arg `{ _, enabled in ... }` form. Body uses `enabled`. Correct.
- `LabPreferencesView.swift`: 0 onChange sites. `if #available(macOS 12, *)` guard removed; `.onSubmit { commitMusixmatchToken() }` kept unconditionally at line 149. `onSubmit` is unconditionally available on macOS 15+. No behavior loss. Comment in doc-comment and inline comment correctly stripped (macOS 11–12 unreliability language gone; Coordinator rationale updated to be version-neutral).

**LabPreferencesView `if #available` removal confirmed:**
Read lines 143–150 on disk: `musixmatchTextField` computes to a single `TextField` with `.textFieldStyle(.roundedBorder)`, `.frame(maxWidth: 260)`, and `.onSubmit { commitMusixmatchToken() }` — no guard, no else branch. Identical behavior to the old macOS 12+ branch.

**Default Debug clean build:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug clean build
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase3-review.log   → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase3-review.log → 31
grep -nE "warning:.*onChange|onChange\(of:\) action with" /tmp/lyricsx-phase3-review.log → (no output — 0 onChange deprecation warnings)
grep -nE "warning:" /tmp/lyricsx-phase3-review.log | grep -i 'preferences/' → 2 hits (SMLoginItemSetEnabled deprecated in macOS 13, GeneralPreferencesView.swift lines 77+85)
```
The 2 Preferences-path warnings are for `SMLoginItemSetEnabled` deprecation — pre-existing, not introduced by Phase 3, and out of Phase 3 scope.

Remaining 31 warnings sample (all outside Phase 3 scope):
- 11× `FrameworkToolboxMacros` missing dependency (SPM macro dep graph)
- 2× `SMLoginItemSetEnabled` deprecated macOS 13 (GeneralPreferencesView.swift — pre-existing)
- 2× DFRPrivate umbrella header (TouchBarHelper dep)
- 2× `appStoreReceiptURL` deprecated macOS 15 (AppEnvironment.swift)
- 1× `init(contentsOf:)` deprecated macOS 15 (DragNDropView.swift)
- 2× `filePromise` deprecated macOS 10.14 (SearchLyricsViewController.swift)
- 1× `keyedUnarchiveFromDataTransformerName` deprecated macOS 10.14 (Observation.swift)
- 1× Main.storyboard "Preferences" unreachable (Phase 5 scope)
- 1× Main.storyboard SF Symbol deprecated
- Remaining: appintentsmetadataprocessor advisory

**IS_FOR_MAS build:**
```
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS'
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' /tmp/lyricsx-phase3-review-mas2.log → 0
grep -cE '\bwarning:' /tmp/lyricsx-phase3-review-mas2.log → 21 (all pre-existing, none in Preferences Phase 3 files)
```
Note: first IS_FOR_MAS run failed with database lock error due to concurrent builds — re-run succeeded cleanly.

**State doc consistency check:**
- `## Current status`: updated to "Last completed phase: Phase 3 review", "Current phase: Phase 4 (pending)".
- `## Phase checklist`: Phase 3 impl `[x]`, Phase 3 review `[x]`.
- `## Decisions`: D3.1 (onChange form selection), D3.2 (Coordinator kept), D3.3 (Up/Down buttons kept) — all present with rationale.
- `## Changed files by phase`: Phase 3 subsection lists 4 Preferences files with per-file change counts. Counts match diff inspection.
- `## Verification log`: Phase 3 implementation entry present; this Phase 3 review entry added.

**Patches applied by this review:**
- `## Current status`: updated "Current phase" to "Phase 4 (pending)", "Last completed phase" to "Phase 3 review — verified 2026-05-23", "Build status" to Phase 3 review build counts.
- `## Phase checklist`: marked `Phase 3 review` as `[x]`.
- `## Resume instructions`: updated below.

**Overall verdict: PASS. No defects found. Green light for Phase 4.**

---

### Phase 2 review

**2026-05-23 — Independent verification by Phase 2 review subagent:**

**git status check:**
```
git status --short
```
Result: `M CLAUDE.md`, `M Lirico.xcodeproj/project.pbxproj`, `M Lirico/Preferences/ShortcutPreferencesView.swift`, `M Lirico/Utility/Extension.swift`, `M LiricoPackage/Package.swift`, `M README.md`, `M docs/implementation/preferences-swiftui-migration.md`, `?? docs/implementation/preferences-swiftui-modernization-followup.md`. Exactly the expected Phase 1 + Phase 2 files. No stray modifications.

**Fix 1 — MAS hiding condition (ShortcutPreferencesView.swift):**

IBInspection.swift source-of-truth (lines 36–42):
```swift
#if IS_FOR_MAS
if newValue, defaults[.isInMASReview] != false {
    removeFromSuperview()
}
#endif
```

ShortcutPreferencesView.swift (lines 54–62) as read on disk:
```swift
#if IS_FOR_MAS
if defaults[.isInMASReview] != false {
    EmptyView()
} else {
    shortcutRow("Search lyrics", key: "ShortcutSearchLyrics")
}
#else
shortcutRow("Search lyrics", key: "ShortcutSearchLyrics")
#endif
```

Condition matches. `newValue` is elided — correct per D2.1, because the storyboard always set `isRemovedDuringMASReview = true`. The `#if IS_FOR_MAS` block wraps ONLY the "Search lyrics" / `ShortcutSearchLyrics` row; the surrounding rows ("Write lyrics to Apple Music" and "Mark as wrong lyrics") are unaffected. `key:` is `"ShortcutSearchLyrics"` — exact expected UserDefaults key string.

**ViewBuilder context check:** `lyricsActionsSection` returns `some View` via `SettingsSection(title:) { ... }`. The trailing closure is a `@ViewBuilder`-annotated content parameter. A bare `if/else` with `EmptyView()` and a `shortcutRow(...)` call inside a `@ViewBuilder` closure is valid SwiftUI — no `Group` wrapper needed. Verified by inspecting the full view body above the `#if` block (lines 51–65).

**Fix 2 — Font fallback (Extension.swift lines 89–95):**

`lyricsWindowFont` property (as read on disk):
```swift
var lyricsWindowFont: NSFont {
    return NSFont(
        name: defaults[.lyricsWindowFontName],
        size: CGFloat(defaults[.lyricsWindowFontSize])
    )
        ?? NSFont.labelFont(ofSize: CGFloat(defaults[.lyricsWindowFontSize]))
}
```
Fallback now correctly uses `defaults[.lyricsWindowFontSize]`. Bug fixed.

`desktopLyricsFont` (lines 80–87) still uses `defaults[.desktopLyricsFontSize]` in both primary and fallback — symmetry confirmed, sibling property untouched.

Both keys confirmed in UserDefaultsKeys.swift:
- `desktopLyricsFontSize`: `Key<Int>("DesktopLyricsFontSize")` (line 51)
- `lyricsWindowFontSize`: `Key<Int>("LyricsWindowFontSize")` (line 60)

**Fix 3 — Migration doc corrective note:**

`docs/implementation/preferences-swiftui-migration.md` lines 14–15 (as read on disk):
```md
- [ ] Phase 0 review
  > Phase 0 review was deferred at migration time and is being completed by the modernization follow-up; see docs/implementation/preferences-swiftui-modernization-followup.md.
```
Checkbox unchecked, corrective blockquote note present and unambiguous. Accurate historical record preserved.

**IS_FOR_MAS flag context:**
```
grep -RIn 'IS_FOR_MAS' Lirico.xcodeproj/project.pbxproj Lirico/ LiricoHelper/ LiricoPackage/
```
Result: `ShortcutPreferencesView.swift:54` (1 occurrence), `IBInspection.swift:10`, `IBInspection.swift:22`, `IBInspection.swift:36` (3 occurrences). No `.xcconfig` files in the project tree (only in DerivedData dependency checkouts). `SWIFT_ACTIVE_COMPILATION_CONDITIONS = ""` at project level (line 905). Flag not defined in any build configuration. Consistent with D2.3.

**Default Debug build:**
```
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' → 0
grep -cE '\bwarning:' → 0 (incremental)
```

**IS_FOR_MAS forced build (critical — MAS branch compilation):**
```
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG IS_FOR_MAS'
→ ** BUILD SUCCEEDED **
grep -cE '\berror:' → 0
```
The `#if IS_FOR_MAS` branch in `ShortcutPreferencesView.swift` compiles cleanly under a forced-flag build. No ViewBuilder ambiguity, no missing `Group` wrapper, no type errors.

Warning count: 0 in incremental builds. Full-rebuild baseline from Phase 1 was 13 `onChange` deprecation warnings — those remain in place and are Phase 3's target. No new warnings introduced by Phase 2.

**State doc consistency check:** All required sections present. `## Current status` updated. `## Phase checklist` Phase 2 `[x]`, Phase 2 review `[x]`. `## Decisions` has D2.1, D2.2, D2.3 entries with IBInspection.swift quotes. `## Changed files by phase` Phase 2 subsection lists all 3 changed files with rationale. `## Verification log` has Phase 2 implementation entry.

**Patches applied by this review:**
- `## Current status`: "Current phase" updated to "Phase 3 (pending)", "Last completed phase" updated to "Phase 2 review — verified 2026-05-23", "Build status" updated to include IS_FOR_MAS build.
- `## Phase checklist`: marked `Phase 2 review` as `[x]`.
- `## Verification log`: added this Phase 2 review entry.
- `## Resume instructions`: updated to reflect Phase 2 review completion and Phase 3 as next step.

**Overall verdict: PASS. No defects found. Green light for Phase 3.**

## Resume instructions

**Follow-up complete.** If resuming for a new follow-up pass, start by reading this state doc + `git log` to see what's already done.

**State as of Phase 5 review (2026-05-23):**

- All phases 0–5 implementation and review: complete and passing.
- Build: PASS — 0 errors, 30 warnings (all out of scope).
- No commits made (per orchestrator "do not commit" rule).

**Known deferred items:**
- **D4.2** — Deferred localization salvage: Old `mul.lproj/Preferences.xcstrings` translations (18 locales) are recoverable from git commit `e9e1398bada999be8280bb0e67f50b16d53fa27f~1`. See D4.2 for the recommended salvage approach.
- **D2.3** — IS_FOR_MAS not defined in any build configuration. MAS submission requires adding `IS_FOR_MAS` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for the MAS Release configuration.
- **D5.3** — `AppDelegate.swift:176` `if #available(macOS 11, *)` guard is now dead code given macOS 15+ deployment target. Needs a separate cleanup pass.
