# SR-05 — Evaluated pipeline events, ranking config, and strict-search removal

## Goal

Make `LyricsSearchPipeline` emit app-level evaluated search events, wire in ranking configuration from app settings, and remove the legacy strict-search gate once the evaluated path exists.

## Depends on / blocks

- **Depends on:** `SR-03`, `SR-04`
- **Blocks:** `SR-06`, `SR-07`

## Scope

- Add app-level `LyricsSearchEvent` and `LyricsSearchPipeline.events(...)`.
- Map raw LyricsKit provider events into app-level provider/candidate events.
- Canonicalize `lyrics.metadata.service` from provider-event source before preparation/evaluation leaves the pipeline.
- Prepare candidates, evaluate them, assign `arrivalIndex`, and emit `EvaluatedLyricsCandidate` payloads.
- Add `SearchSettings.rankingConfiguration`.
- Preserve or provide a short-lived compatibility wrapper only if needed for downstream callers during migration.
- Remove old strict-search preference usage and `strict`/`Lyrics.isMatched()` filtering once consumers are on the evaluated path.
- Remove or repurpose `LyricsSelector` APIs that are obsolete under ranker-driven behavior.

## Out of scope

- Manual search UX/state changes.
- Automatic search deadline/local-upgrade policy changes.
- Final threshold tuning and broad cleanup.

## Likely touchpoints

- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSelector.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Preferences/GeneralPreferencesView.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Utility/UserDefaultsKeys.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Source identity and source priority**, **Provider feedback**, **Pipeline/workflow changes**, **Selector changes**, **Resolved decisions**
- `../phases.md` — **Phase 2**, **Key ordering corrections**

Must honor:
- The app-level pipeline event stream is non-throwing.
- `.candidate` events include `.unlikely` and `.rejected` evaluations; consumers decide visibility.
- No `completed` after cancellation or deadline termination.
- Strict-search removal belongs here, not as a manual-only change.
- Ranking configuration remains app-side, but evaluator/ranker types remain package-side.

## Acceptance criteria

- `LyricsSearchPipeline` can stream provider lifecycle events plus evaluated candidates.
- Consumers can get request-scoped `arrivalIndex`, canonical source names, and evaluation payloads from one pipeline surface.
- `SearchSettings` exposes ranking configuration for the new ranker.
- The old strict-search preference/path is no longer the primary correctness gate.
- The app compiles with the manual/automatic callers ready to migrate to the new pipeline.

## Risks or ambiguity

- This is a merge hot spot between shared domain work and both consumer branches.
- Removing strict-search too early can strand existing callers; keep the migration boundary explicit.