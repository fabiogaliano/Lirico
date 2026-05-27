# Orchestrator prompt — SwiftUI Preferences follow-up and macOS 15 modernization

You are the main AI coding-agent orchestrator for a follow-up pass on the SwiftUI Preferences migration in Lirico, a macOS menu-bar lyrics app at:

/Users/f/Core/dev/projects/Lirico

The previous migration replaced the old storyboard Preferences UI with SwiftUI. This follow-up pass should review, patch, and modernize that work, with permission to raise the app's minimum deployment target up to **macOS 15+** when doing so simplifies the code and improves maintainability.

The orchestrator controls scope, sequencing, and review. Implementation work should be delegated phase-by-phase to subagents. After every implementation phase, launch a fresh review subagent to inspect the diff, run checks/build, and either patch small safe issues or report what needs a follow-up patch.

This should run autonomously. Do not ask the human for routine implementation decisions. When the plan is unclear, make the safest reversible decision that preserves behavior, record the decision and rationale in the follow-up state document, and continue.

Do not commit.

## Primary goals

- Patch known regressions or incomplete migration details from the SwiftUI Preferences migration.
- Raise deployment target to macOS 15+ if it makes the code cleaner and removes compatibility hacks.
- Use modern SwiftUI APIs where the new target allows it.
- Preserve user-facing behavior and stored preferences unless explicitly modernizing deprecated/compatibility implementation details.
- Keep changes phased, reviewable, and documented.

## Known items to handle

From review of current git changes:

1. `ShortcutSearchLyrics` no longer respects the old storyboard `isRemovedDuringMASReview` behavior.
2. `docs/implementation/preferences-swiftui-migration.md` says migration complete but still has Phase 0 review unchecked.
3. Pre-existing bug in `Lirico/Utility/Extension.swift`: `lyricsWindowFont` fallback uses `desktopLyricsFontSize` instead of `lyricsWindowFontSize`.
4. SwiftUI uses deprecated `onChange(of:)` single-argument closures. This is acceptable for macOS 11, but should be modernized if the deployment target is raised.
5. Several macOS 11/12 compatibility branches/comments remain in Preferences SwiftUI code.
6. Localization needs a deliberate decision: old `mul.lproj/Preferences.xcstrings` was removed and new SwiftUI labels were added to `Localizable.xcstrings`, including likely extraction junk keys like `""`, `".*"`, and `"%lld"`.

## Autonomy rules

The human may leave this running unattended. The orchestrator and subagents should proceed without asking questions unless blocked by something destructive, credential-related, externally visible, or impossible to decide safely.

Default decision policy:

- Preserve existing runtime behavior over visual polish.
- Prefer the smallest reversible patch.
- Prefer modern SwiftUI/AppKit APIs once the target is raised to macOS 15+.
- Prefer deleting compatibility hacks after deployment target bump.
- Prefer explicit, documented behavior over storyboard-only/runtime-attribute behavior.
- Prefer keeping localization valid over attempting full translation migration.
- If localization choices are unclear, preserve existing translations where practical and record deferred translation work.
- If MAS review behavior is unclear, preserve the previous hiding behavior because it existed before migration.

Every non-obvious decision made because the plan was unclear must be logged in:

- `docs/implementation/preferences-swiftui-modernization-followup.md`

under `## Decisions` or `## Unknowns resolved autonomously`.

Each logged decision should include:

- phase,
- decision,
- alternatives considered,
- rationale,
- risk,
- deferred follow-up, if any.

Subagents must also add their decisions and unknowns to the same document. The orchestrator must review that section after every phase.

## Persistent progress and context safeguards

Create and maintain:

- `docs/implementation/preferences-swiftui-modernization-followup.md`

This document is the source of truth if context is lost or a new agent resumes work.

Required structure:

```md
# Preferences SwiftUI modernization follow-up

## Current status

- Current phase:
- Last completed phase:
- Build status:
- Known blockers:

## Phase checklist

- [ ] Phase 0 — Audit current diff and target bump plan
- [ ] Phase 0 review
- [ ] Phase 1 — Deployment target macOS 15+ modernization
- [ ] Phase 1 review
- [ ] Phase 2 — Known behavior regressions and bug fixes
- [ ] Phase 2 review
- [ ] Phase 3 — SwiftUI API cleanup
- [ ] Phase 3 review
- [ ] Phase 4 — Localization cleanup
- [ ] Phase 4 review
- [ ] Phase 5 — Final cleanup and verification
- [ ] Phase 5 review

## Current migration diff summary

Summarize current changed files and what they do.

## Decisions

Record architecture, UX, compatibility, localization, and implementation decisions.

## Unknowns resolved autonomously

Record unclear requirements encountered, assumptions made, and why the chosen path was safe/reversible.

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
- If context is lost, the next orchestrator must read this state document, this prompt, and `git status --short` before continuing.

## Required first-read context

Read before Phase 0 planning:

- `CLAUDE.md`
- `docs/implementation/preferences-swiftui-migration.md`
- current SwiftUI Preferences files:
  - `Lirico/Preferences/PreferenceWindowController.swift`
  - `Lirico/Preferences/PreferencesView.swift`
  - `Lirico/Preferences/SettingsSection.swift`
  - `Lirico/Preferences/GeneralPreferencesView.swift`
  - `Lirico/Preferences/DisplayPreferencesView.swift`
  - `Lirico/Preferences/ShortcutPreferencesView.swift`
  - `Lirico/Preferences/FilterPreferencesView.swift`
  - `Lirico/Preferences/LabPreferencesView.swift`
  - `Lirico/Preferences/SourcePreferencesView.swift`
  - `Lirico/Preferences/NowPlayingApplicationListViewController.swift`
- relevant utilities/settings:
  - `Lirico/Utility/Extension.swift`
  - `Lirico/Utility/IBInspection.swift`
  - `Lirico/Utility/UserDefaultsKeys.swift`
  - `Lirico/Component/UserDefaultsRegistration.swift`
  - `Lirico/Component/PersistenceSettings.swift`
  - `Lirico/Component/SearchSettings.swift`
  - `Lirico/Component/PlayerSettings.swift`
  - `Lirico/Component/DisplaySettings.swift`
  - `Lirico/Component/ExportSettings.swift`
- project/package/docs that mention deployment target:
  - `Lirico.xcodeproj/project.pbxproj`
  - `LiricoPackage/Package.swift`
  - `README.md`
  - `CLAUDE.md`
  - release notes that mention minimum macOS version
- localization files touched by the migration:
  - `Lirico/Supporting Files/Localizable.xcstrings`
  - deleted/current `Lirico/mul.lproj/Preferences.xcstrings` via git history if needed

Also run:

```bash
git status --short
git diff --stat
git diff --name-only
```

Do not overwrite unrelated user changes.

## Orchestration protocol

For each phase:

1. The orchestrator creates a focused implementation subagent prompt with:
   - phase goal,
   - files to read,
   - files likely to edit,
   - explicit non-goals,
   - autonomy rules,
   - requirement to log decisions/unknowns in the follow-up state document,
   - verification commands,
   - expected final report.
2. The implementation subagent performs only that phase.
3. The implementation subagent builds/checks when practical and reports changed files and risks.
4. The orchestrator launches a fresh review subagent.
5. The review subagent:
   - reads the phase goal and changed files,
   - reads the follow-up state document decisions/unknowns for the phase,
   - inspects the diff,
   - runs targeted greps/checks/build when practical,
   - patches small safe issues directly if allowed by the orchestrator,
   - records review findings and any review-time decisions in the state document,
   - otherwise reports required follow-up patches.
6. If review finds issues, the orchestrator launches a focused patch subagent or asks the review subagent to patch only those issues.
7. The orchestrator proceeds to the next phase only when review is clean enough.

Do not let one subagent run ahead into later phases.

## Phase plan

### Phase 0 — Audit current diff and target bump plan

Implementation subagent goal:

- Create `docs/implementation/preferences-swiftui-modernization-followup.md`.
- Audit the current uncommitted SwiftUI Preferences migration diff.
- Confirm build status and current deployment targets.
- Identify all macOS 11/12/13 compatibility branches in new Preferences code.
- Identify all deprecated `onChange(of:)` call sites in new Preferences code.
- Identify localization files touched and likely junk keys.
- Propose exact Phase 1–5 file list.
- Do not edit production code in Phase 0.

Deliverable:

- State document with phase checklist, current diff summary, risks, proposed file list, and resume instructions.

Review subagent goal:

- Verify the audit against actual git diff and code.
- Confirm no known item is missing.
- Confirm the state document is sufficient to resume after context loss.

### Phase 1 — Deployment target macOS 15+ modernization

Implementation subagent goal:

- Raise minimum macOS deployment target to macOS 15+ where relevant.
- Update Xcode project deployment targets for app/helper/package targets as appropriate.
- Update `LiricoPackage/Package.swift` platform from macOS 11 to macOS 15 if compatible with dependencies.
- Update docs that state macOS 11+ minimum requirement.
- Remove or update prompt/state references that incorrectly say macOS 11+ is still required.
- Do not change runtime preference behavior in this phase except what is necessary for the target bump.

Likely files:

- `Lirico.xcodeproj/project.pbxproj`
- `LiricoPackage/Package.swift`
- `README.md`
- `CLAUDE.md`
- release notes if they state current minimum requirement
- `docs/implementation/preferences-swiftui-modernization-followup.md`

Review subagent goal:

- Verify all deployment target declarations are consistent.
- Verify package still resolves/builds.
- Verify docs no longer claim macOS 11+ where that is now false.
- Build/check.

### Phase 2 — Known behavior regressions and bug fixes

Implementation subagent goal:

Patch known behavior issues:

1. Restore MAS review hiding behavior for `ShortcutSearchLyrics`.
   - Old storyboard used `isRemovedDuringMASReview` on the `ShortcutSearchLyrics` label/view.
   - Implement explicit SwiftUI conditional hiding equivalent.
   - Preserve non-MAS behavior.
2. Fix `lyricsWindowFont` fallback bug in `Lirico/Utility/Extension.swift`.
   - Fallback should use `lyricsWindowFontSize`, not `desktopLyricsFontSize`.
3. Mark Phase 0 review complete in `docs/implementation/preferences-swiftui-migration.md` if review truly happened, or record a corrective note if it did not.

Non-goals:

- Do not do broad SwiftUI API cleanup here.
- Do not do localization cleanup here.

Likely files:

- `Lirico/Preferences/ShortcutPreferencesView.swift`
- `Lirico/Utility/Extension.swift`
- `docs/implementation/preferences-swiftui-migration.md`
- follow-up state document

Review subagent goal:

- Verify MAS review behavior matches old `IBInspection.swift` semantics.
- Verify font fallback fix is correct and isolated.
- Verify migration state doc consistency.
- Build/check.

### Phase 3 — SwiftUI API cleanup for macOS 15+

Implementation subagent goal:

- Replace deprecated single-argument `onChange(of:)` closures with modern macOS 14+/15-compatible forms.
- Remove macOS 11/12 compatibility branches and comments in Preferences SwiftUI code.
- Simplify sheet/workaround code where macOS 15 makes it safe.
- Prefer modern SwiftUI controls/styles available on macOS 15 if it reduces code and risk.
- Keep behavior unchanged.

Likely files:

- `Lirico/Preferences/GeneralPreferencesView.swift`
- `Lirico/Preferences/DisplayPreferencesView.swift`
- `Lirico/Preferences/LabPreferencesView.swift`
- `Lirico/Preferences/SourcePreferencesView.swift`
- maybe `SettingsSection.swift`

Review subagent goal:

- Verify all `onChange(of:)` deprecation sites in Preferences are updated.
- Verify removed compatibility code had no behavior now needed for macOS 15.
- Build/check with warnings scan.

### Phase 4 — Localization cleanup

Implementation subagent goal:

- Review `Lirico/Supporting Files/Localizable.xcstrings` changes from migration.
- Remove accidental/junk extraction keys introduced by SwiftUI migration, especially keys like:
  - empty string `""`,
  - `".*"`,
  - numeric/string-format artifacts such as `"%lld"` if not intentionally user-facing.
- Decide what to do with deleted `Lirico/mul.lproj/Preferences.xcstrings`:
  - If the SwiftUI Preferences no longer uses storyboard string-catalog IDs, deletion may be valid.
  - Preserve old translations only if they can be mapped safely to new plain-English keys without corrupting localization.
  - If full mapping is too risky, record deferred localization migration clearly.
- Ensure string catalogs remain valid JSON.

Non-goals:

- Do not run BartyCrouch or Crowdin tooling.
- Do not invent translations.

Review subagent goal:

- Verify `Localizable.xcstrings` parses as JSON/string catalog.
- Verify no obvious junk keys remain.
- Verify no existing non-Preferences translations were lost.
- Build/check.

### Phase 5 — Final cleanup and verification

Implementation subagent goal:

- Search for stale references to deleted Preferences storyboard/classes/files in production code and project file.
- Search for stale macOS 11/12 compatibility comments in Preferences migration files after the target bump.
- Remove dead docs or update state docs where they are misleading.
- Run final build/checks.
- Record final status and remaining risks.

Review subagent goal:

- Run final grep checks:
  - deleted Preferences classes/files are not referenced in production code,
  - `Preferences.storyboard` is not referenced by project/resources,
  - `onChange(of:)` deprecated forms are not present in Preferences files,
  - deployment target mentions are consistent,
  - string catalog parses.
- Run build/check.
- Record final review result.

## Build and checks

Preferred build:

```bash
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build 2>&1 | xcsift
```

If `xcsift` is unavailable:

```bash
xcodebuild -project Lirico.xcodeproj -scheme Lirico -configuration Debug build
```

Also run when practical:

```bash
git diff --check
plutil -lint Lirico.xcodeproj/project.pbxproj
python3 -m json.tool "Lirico/Supporting Files/Localizable.xcstrings" >/dev/null
```

For warning scan after build:

```bash
grep -E "warning:|error:" /tmp/lyricsx-build.log
```

## Final orchestrator summary

At the end, summarize:

- Phases completed.
- Deployment target changes made.
- Known issues patched.
- SwiftUI modernization changes made.
- Localization cleanup outcome and deferred localization work, if any.
- Behavior/settings preserved.
- Build/check result.
- Review findings and patches applied after each phase.
- Remaining risks or manual verification needed.
