# SR-08 — Hardening, tuning, and cleanup

## Goal

Finish the overhaul by expanding automated coverage, tuning thresholds against real examples, and removing transitional scaffolding that should not survive the rollout.

## Depends on / blocks

- **Depends on:** `SR-02`, `SR-06`, `SR-07`
- **Blocks:** none

## Scope

- Fill out the required LyricsXFoundation evaluator/ranker tests from the plan.
- Fill out the required LyricsKit provider-event/LRCLIB tests from the plan.
- Tune threshold constants with real examples if implementation findings require adjustment.
- Remove leftover compatibility shims, dead strict-search UI/defaults, and obsolete `priorityWindow` behavior if still present.
- Run the relevant package tests and app build verification.

## Out of scope

- New product behavior beyond the approved plan.
- Provider-specific rich-timing enhancements.
- Duplicate-row grouping or broader search UI redesign.

## Likely touchpoints

- `/Users/f/Core/dev/projects/LyricsX/LyricsXPackage/Tests/LyricsXFoundationTests/`
- `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/SearchSettings.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Utility/UserDefaultsKeys.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Preferences/GeneralPreferencesView.swift`
- `/Users/f/Core/dev/projects/LyricsX/LyricsX/Component/LyricsSelector.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Testing strategy**, **Resolved decisions**
- `../phases.md` — **Phase 5**

Must honor:
- Do not weaken tests to match broken behavior.
- Threshold tuning must stay inside the approved ranking rules.
- Cleanup should only remove paths made obsolete by merged implementation, not speculative code.

## Acceptance criteria

- The required evaluator/ranker cases from the plan are covered by package tests.
- The required LyricsKit provider-event/LRCLIB cases from the plan are covered by tests.
- LyricsX builds cleanly against the intended dependency setup.
- No active strict-search path remains.
- Final ranking behavior is verified by automated tests, not only manual checks.

## Risks or ambiguity

- Cleanup can become a grab bag; keep it limited to dead transitional code and approved tuning.
- Threshold changes should be justified by concrete examples or failing tests, not intuition alone.