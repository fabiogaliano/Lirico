# Orchestrator prompt — SwiftUI Preferences migration

You are the main AI coding-agent orchestrator for modernizing the Settings/Preferences UI of Lirico, a macOS menu-bar lyrics app at:

/Users/f/Core/dev/projects/Lirico

Your job is to coordinate a phased migration of Preferences to SwiftUI using the quickest safe path. The orchestrator controls scope, sequencing, and review. Implementation work should be delegated phase-by-phase to subagents. After every implementation phase, launch a fresh review subagent to inspect the diff, build/check the app, and either patch small issues or report what needs a follow-up patch.

This should run autonomously. Do not ask the human for routine implementation decisions. When the plan is unclear, make the safest reversible decision that preserves behavior, record the decision and rationale in the migration state document, and continue.

Do not commit.

## Autonomy rules

The human may leave this running unattended. The orchestrator and subagents should proceed without asking questions unless blocked by something destructive, credential-related, externally visible, or impossible to decide safely.

Default decision policy:

- Preserve existing behavior over visual polish.
- Prefer the smallest reversible implementation.
- Prefer AppKit bridges when native SwiftUI would risk behavior changes.
- Prefer existing settings wrappers over new abstractions.
- Prefer compatibility with macOS 11 over newer-only APIs.
- Prefer keeping old code temporarily over deleting too early.
- If two UI choices are equivalent, choose the clearer, simpler, more standard macOS option.
- If uncertain whether to migrate a risky control now, bridge it first and record it as deferred SwiftUI-native cleanup.

Every non-obvious decision made because the plan was unclear must be logged in `docs/implementation/preferences-swiftui-migration.md` under `## Decisions`. Include:

- date/time if readily available,
- phase,
- decision,
- alternatives considered,
- why this option was chosen,
- risk/deferred follow-up, if any.

Subagents must also add their own decisions and unknowns to the same document. The orchestrator must review that section after every phase so the human can wake up and read what was decided and why.

## High-level direction

Use a hybrid AppKit + SwiftUI migration.

- Keep the existing AppKit app lifecycle.
- Keep the rest of Lirico AppKit.
- Do not use UIKit or Catalyst.
- Replace or bypass the old Preferences storyboard internals with an `NSHostingController` hosting SwiftUI Preferences.
- Migrate one slice at a time.
- Preserve existing defaults, settings wrappers, actions, keyboard shortcuts, source ordering, filters, color/font behavior, and user workflows.
- Use AppKit bridges (`NSViewRepresentable` / `NSViewControllerRepresentable`) where that is safer than forcing a native SwiftUI rewrite.

Primary outcome: Preferences should be easier to understand, faster to use, and easier to maintain. Improve UX, not just visuals: simplify choices, clarify labels, reduce clutter, group related settings, and make the common path obvious.

## Answer for color/alpha controls

For SwiftUI, the modern first choice is `ColorPicker(..., supportsOpacity: true)` if it preserves the existing alpha behavior and saved color format correctly.

However, Lirico already has `AlphaColorWell`, which explicitly enables alpha in `NSColorPanel`. For the safest migration:

1. Try SwiftUI `ColorPicker` only if the pane can bind reliably to the existing stored color values including alpha.
2. If color fidelity, alpha persistence, or `NSColor` bridging is uncertain, keep behavior by wrapping `AlphaColorWell` in `NSViewRepresentable`.
3. When bridging `NSColorWell`, use `colorWellStyle = .minimal` only behind `if #available(macOS 13, *)`; deployment target is macOS 11+.

In short: `ColorPicker(supportsOpacity: true)` is the modern SwiftUI option; `AlphaColorWell` bridge is the safest compatibility option.

## UX goals for every phase

- Make each pane clear, concise, and direct.
- Prefer plain-language labels over technical wording when behavior can stay unchanged.
- Group settings by user task, not implementation detail.
- Remove visual noise: avoid decorative boxes, redundant labels, repeated explanations, and excessive separators.
- Use short inline help only where it prevents confusion or explains consequences.
- Put primary/common controls first; move advanced or rarely used controls lower.
- Keep panes scannable with consistent section titles, row layout, spacing, and control placement.
- Preserve existing behavior, defaults, bindings/actions, and storage keys.
- Do not add new preferences or speculative features.

## Required first-read context for the orchestrator and relevant subagents

Read before planning Phase 0:

- `CLAUDE.md`
- `Lirico/Base.lproj/Preferences.storyboard`
- `Lirico/Preferences/PreferenceViewController.swift`
- `Lirico/Preferences/PreferenceWindowController.swift`
- `Lirico/Preferences/PreferenceGeneralViewController.swift`
- `Lirico/Preferences/PreferenceDisplayViewController.swift`
- `Lirico/Preferences/PreferenceShortcutViewController.swift`
- `Lirico/Preferences/PreferenceFilterViewController.swift`
- `Lirico/Preferences/PreferenceLabViewController.swift`
- `Lirico/Preferences/PreferenceSourceViewController.swift`
- `Lirico/Preferences/AlphaColorWell.swift`
- `Lirico/Preferences/FilterKey.swift`
- `Lirico/Preferences/NowPlayingApplicationListViewController.swift`
- `Lirico/View/FontSelectTextField.swift`
- `Lirico/Supporting Files/UserDefaults.plist`
- Settings wrappers:
  - `Lirico/Component/DisplaySettings.swift`
  - `Lirico/Component/PersistenceSettings.swift`
  - `Lirico/Component/SearchSettings.swift`
  - `Lirico/Component/ExportSettings.swift`
  - `Lirico/Component/PlayerSettings.swift`
  - `Lirico/Component/UserDefaultsRegistration.swift`

Also run before any implementation:

```bash
git status --short
```

Do not overwrite unrelated user changes.

## Current Preferences structure

Current storyboard shell:

- `Lirico/Base.lproj/Preferences.storyboard`
- `PreferenceTabViewController`
- storyboard id: `sV3-nO-PkZ`
- `NSTabViewController`
- `tabStyle="toolbar"`

Current tabs, in order:

1. General — `PreferenceGeneralViewController`
2. Display — `PreferenceDisplayViewController`
3. Shortcut — `PreferenceShortcutViewController`
4. Filter — `PreferenceFilterViewController`
5. Lab — `PreferenceLabViewController`
6. Source — `PreferenceSourceViewController`

SwiftUI Preferences should keep this order unless there is a strong UX reason to change it.

## Architecture constraints

Create a small SwiftUI Preferences module under `Lirico/Preferences/`, for example:

- `PreferencesView.swift`
- `PreferenceControls.swift` or `SettingsControls.swift`
- `GeneralPreferencesView.swift`
- `DisplayPreferencesView.swift`
- `ShortcutPreferencesView.swift`
- `FilterPreferencesView.swift`
- `LabPreferencesView.swift`
- `SourcePreferencesView.swift`
- AppKit bridges as needed:
  - `AlphaColorWellRepresentable.swift`
  - `FontPickerRepresentable.swift`
  - `ShortcutRecorderRepresentable.swift`
  - `SourcePriorityTableRepresentable.swift`

Keep helpers concrete and minimal. Do not build a generic UI framework.

Prefer existing settings wrappers rather than new raw defaults access:

- `DisplaySettings`
- `PersistenceSettings`
- `SearchSettings`
- `ExportSettings`
- `PlayerSettings`
- `UserDefaultsRegistration`

If a wrapper does not expose a SwiftUI-friendly binding, add a minimal local `ObservableObject` view model for that pane.

View model rules:

- Keep one small view model per pane only when needed.
- View models call existing wrappers/actions.
- Do not duplicate business rules in SwiftUI views.
- Preserve defaults keys and values.
- Keep AppKit-only side effects in methods, not scattered through SwiftUI bodies.
- Do not reintroduce hidden lazy defaults observers or app-wide static cached state.

Recent explicit services must not be undone or bypassed:

- `ChineseConverterProvider`
- `LyricsFilter`
- `LyricsPreparation`

## Design/availability constraints

Use `/macos-design` if available before Phase 0 planning. Treat CSS/web examples as conceptual only.

Deployment target is macOS 11+.

- Use simple SwiftUI APIs available on macOS 11 where possible.
- Gate macOS 12/13+ APIs with `if #available`.
- Use SF Symbols for tab/icons.
- Do not add Phosphor unless SF Symbols cannot express the concept. If added, mention it clearly in the final summary.

Suggested reusable SwiftUI layout:

```swift
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
}
```

Adjust to project style and macOS 11 compatibility.

## Storyboard rules

Do not heavily edit storyboard XML.

Allowed storyboard changes:

- Keep storyboard temporarily as a shell if fastest.
- Bypass or remove old pane internals after SwiftUI Preferences is wired.
- Preserve entry points used elsewhere.
- Preserve window/controller IDs where practical.

If replacing the storyboard-based Preferences window entirely is simpler and safe, do it in `PreferenceWindowController` while preserving `PreferenceWindowController.create()` and existing call sites.

## Build/check commands

Preferred build:

```bash
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | xcsift
```

If `xcsift` is unavailable:

```bash
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build
```

Always run when practical:

```bash
git diff --check
plutil -lint Lirico.xcodeproj/project.pbxproj
```

## Persistent progress, decisions, and context safeguards

Create and maintain a persistent migration state document:

- `docs/implementation/preferences-swiftui-migration.md`

This document is the source of truth if the conversation runs out of context or a new agent needs to resume work. It must be created in Phase 0 and updated after every implementation phase and every review phase.

Required contents:

```md
# Preferences SwiftUI migration

## Current status

- Current phase:
- Last completed phase:
- Build status:
- Known blockers:

## Phase checklist

- [ ] Phase 0 — Audit and migration plan
- [ ] Phase 0 review
- [ ] Phase 1 — SwiftUI shell + Lab tracer bullet
- [ ] Phase 1 review
- [ ] Phase 2 — Shortcut pane
- [ ] Phase 2 review
- [ ] Phase 3 — Filter pane
- [ ] Phase 3 review
- [ ] Phase 4 — General pane
- [ ] Phase 4 review
- [ ] Phase 5 — Display pane
- [ ] Phase 5 review
- [ ] Phase 6 — Source pane
- [ ] Phase 6 review
- [ ] Phase 7 — Cleanup/storyboard retirement
- [ ] Phase 7 review

## Pane migration map

For each pane, record:

- Existing controller/storyboard source
- Settings/defaults touched
- Actions/workflows to preserve
- Native SwiftUI controls planned
- AppKit bridges planned/used
- Review notes

## Decisions

Record architecture, UX, and implementation decisions made because the plan had unknowns or tradeoffs. For each decision, include phase, decision, alternatives considered, rationale, risk, and deferred follow-up.

## Unknowns resolved autonomously

Record any unclear requirements encountered, what assumption was made, and why it was safe/reversible.

## Changed files by phase

Record files added/changed/deleted by each phase.

## Verification log

Record commands run, build results, failures, and fixes.

## Resume instructions

Short instructions for the next agent: where to start, what is done, what remains, and known risks.
```

Rules:

- No phase is complete until this document is updated.
- No review is complete until review findings and patches are recorded.
- No unclear decision is complete until it is recorded under `## Decisions` or `## Unknowns resolved autonomously`.
- If context is lost, the next orchestrator must read this state document, `docs/prompt.md`, and `git status --short` before continuing.
- Keep the document concise but operational. It should let a new agent resume without reading the entire conversation.

## Orchestration protocol

For each phase:

1. The orchestrator creates a focused implementation subagent prompt with:
   - phase goal,
   - files to read,
   - files likely to edit,
   - explicit non-goals,
   - autonomy rules,
   - requirement to log decisions/unknowns in the state document,
   - verification commands,
   - expected final report.
2. The implementation subagent performs only that phase.
3. The implementation subagent builds/checks when practical and reports changed files and risks.
4. The orchestrator launches a fresh review subagent.
5. The review subagent:
   - reads the phase goal and changed files,
   - reads the state document decisions/unknowns for the phase,
   - inspects the diff,
   - runs targeted greps/checks/build when practical,
   - patches small safe issues directly if allowed by the orchestrator,
   - records review findings and any review-time decisions in the state document,
   - otherwise reports required follow-up patches.
6. If review finds issues, the orchestrator launches a focused patch subagent or asks the same review subagent to patch only those issues.
7. The orchestrator proceeds to the next phase only when review is clean enough.

Do not let one subagent run ahead into later phases.

## Phase plan

### Phase 0 — Audit and migration plan only

Implementation subagent goal:

- Read current Preferences storyboard/controllers/settings wrappers.
- Create `docs/implementation/preferences-swiftui-migration.md` using the required structure above.
- Map every pane to current settings, actions, outlets, and custom controls.
- Identify which controls can be native SwiftUI and which should initially be AppKit bridges.
- Propose exact file list for Phase 1.
- Do not edit production code in Phase 0.

Deliverable:

- `docs/implementation/preferences-swiftui-migration.md` with:
  - concise migration map by pane,
  - risks and recommended bridges,
  - phase checklist,
  - current git status,
  - resume instructions.

Review subagent goal:

- Verify the map against the actual code.
- Catch missing controls/actions/settings before implementation starts.
- Confirm the state document is sufficient to resume after context loss.

### Phase 1 — SwiftUI shell + Lab tracer bullet

Implementation subagent goal:

- Add SwiftUI Preferences entry point with `NSHostingController`.
- Add minimal reusable SwiftUI settings section/row components.
- Migrate only the Lab pane first.
- Preserve Lab behavior:
  - Touch Bar lyrics toggle.
  - Touch Bar customization action.
  - Musixmatch token field via `SearchSettings`.
  - Now Playing application customization sheet.
- Keep other panes as placeholders or bridge back to old controllers if needed, but do not fully migrate them.

Likely files:

- `Lirico/Preferences/PreferenceWindowController.swift`
- new `Lirico/Preferences/PreferencesView.swift`
- new `Lirico/Preferences/SettingsControls.swift`
- new `Lirico/Preferences/LabPreferencesView.swift`
- maybe a small Lab view model
- Xcode project file for added Swift files

Review subagent goal:

- Verify the Preferences window still opens from existing call sites.
- Verify Lab behavior is preserved.
- Verify no unrelated panes were accidentally rewritten.
- Build/check.

### Phase 2 — Shortcut pane

Implementation subagent goal:

- Migrate Shortcut pane to SwiftUI.
- Make shortcut rows easy to scan and edit.
- Preserve all shortcut storage keys and existing behavior.
- Bridge existing shortcut recorder controls if present/risky.

Review subagent goal:

- Verify shortcut storage keys/actions remain unchanged.
- Verify UI is not just a visual rewrite with broken recording behavior.
- Build/check.

### Phase 3 — Filter pane

Implementation subagent goal:

- Migrate Filter pane to SwiftUI.
- Make it obvious that enabled filters hide matching lyric lines.
- Keep add/remove/reset actions easy to find.
- Preserve existing behavior:
  - `directFilter`
  - `loadFilter()`
  - `saveFilter()`
  - reset action
  - `.lyricsFilterEnabled`
  - `.lyricsFilterKeys`
- Do not alter `LyricsFilter` semantics.

Review subagent goal:

- Verify filter enable state and keys persist correctly.
- Verify reset behavior.
- Verify no changes to filtering engine semantics.
- Build/check.

### Phase 4 — General pane

Implementation subagent goal:

- Migrate General pane to SwiftUI.
- Simplify grouping around:
  - Music player
  - Startup behavior
  - Lyrics files
  - Language
- Preserve behavior:
  - `PlayerSettings`
  - `PersistenceSettings`
  - `LaunchAtLogin`
  - preferred player behavior
  - player-specific enabling/disabling of beside-track lyrics
  - saving path picker behavior
  - language selection behavior
  - Crowdin translation link

Review subagent goal:

- Verify all previous General actions/settings still exist and persist.
- Verify file picker and language selection behavior.
- Verify player-specific enable/disable logic.
- Build/check.

### Phase 5 — Display pane

Implementation subagent goal:

- Migrate Display pane to SwiftUI.
- Preserve all existing display settings.
- Modernize around:
  - Desktop lyrics font
  - HUD lyrics font
  - Color controls
  - Bilingual/display options
  - Chinese conversion preference if present
- Add a simple preview if practical.
- Use `ColorPicker(... supportsOpacity: true)` only if it preserves alpha and stored color behavior.
- Otherwise bridge `AlphaColorWell` with `NSViewRepresentable`.
- Bridge the existing font picker if replacing it would risk behavior.

Review subagent goal:

- Verify font settings persist and fallback behavior is preserved.
- Verify color alpha persists.
- Verify color controls do not lose existing defaults compatibility.
- Verify Chinese conversion/display options still map to the same settings.
- Build/check.

### Phase 6 — Source pane

Implementation subagent goal:

- Migrate Source pane to SwiftUI.
- Preserve:
  - `SearchSettings.sourcePriorityEnabled`
  - `SearchSettings.sourcePriorityOrder`
  - drag/drop table reordering
  - `LyricsSelector.shared.normalize(...)`
- Fastest safe approach: bridge existing `NSTableView` behavior first if SwiftUI drag/drop is risky.

Review subagent goal:

- Verify enable/disable source priority behavior.
- Verify order persists.
- Verify drag/drop reorder works or existing bridged implementation is preserved.
- Build/check.

### Phase 7 — Cleanup and storyboard retirement pass

Implementation subagent goal:

- Remove obsolete storyboard dependencies only after all SwiftUI panes work.
- Keep required window entry points intact.
- Remove dead outlets/actions/classes only when no longer referenced.
- Keep localization impact minimal.
- Do not remove useful AppKit bridges prematurely.

Review subagent goal:

- Search for dead references and broken outlets/classes.
- Verify project file includes all new Swift files and no deleted files are referenced.
- Run build/check.

## Localization

The project uses:

- `.xcstrings`
- legacy `.strings`
- BartyCrouch
- Crowdin

Do not run localization tooling.

Prefer keeping existing strings where possible. If adding labels/help text, use plain English and mention new strings in the final summary.

## What is already done — do not redo

- Toolbar/preference/HUD/font-picker icons have already been moved toward SF Symbols where applicable.
- Preferences toolbar already uses SF Symbols for:
  - `keyboard`
  - `line.3.horizontal.decrease.circle`
  - `flask`
  - `list.bullet`
- Desktop lyric defaults were modernized:
  - SF Pro Display Semibold
  - 22pt
  - white text
  - system-accent karaoke fill
  - font-scaled padding/corner radius/line gap
  - subtle white border

## Final orchestrator summary

At the end, summarize:

- Phases completed.
- Panes migrated.
- AppKit bridges kept/added and why.
- UX simplifications made: labels, grouping, reduced clutter, help text.
- Behavior/settings preserved.
- Storyboard changes or bypasses.
- New dependencies, if any.
- Build result.
- Review findings and patches applied after each phase.
- Deferred work or risks.
