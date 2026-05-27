# SR-03 — Lirico local LyricsKit integration and canonical source list

## Goal

Move Lirico onto the local LyricsKit API for this work and make Lirico source preferences use the same canonical source names and provider-descriptor construction as the pipeline.

## Depends on / blocks

- **Depends on:** `SR-01`
- **Blocks:** `SR-04`, `SR-05`

## Scope

- Point `LiricoPackage`/Xcode resolution at the intended local LyricsKit dependency path for this implementation effort.
- Migrate provider construction from the old service API to the current `ServiceID`/service factory API.
- Build provider descriptors once and derive the canonical source list from the same construction path.
- Normalize source-priority settings against that canonical list.
- Keep Musixmatch token behavior working with the new provider construction.
- Pass album metadata on automatic current-track requests only where the current request-building surface already exists.

## Out of scope

- Evaluated-candidate pipeline wiring.
- Manual or automatic ranking behavior changes.
- LRCLIB exact-lookup implementation details.

## Likely touchpoints

- `/Users/f/Core/dev/projects/Lirico/LiricoPackage/Package.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSelector.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Component/AppContainer.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico/Preferences/SourcePreferencesView.swift`
- `/Users/f/Core/dev/projects/Lirico/Lirico.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Cross-repo dependency plan**, **Source identity and source priority**, **Phase 0.5**, **Resolved decisions**
- `../phases.md` — **Phase 1**

Must honor:
- `availableLyricsSources` and `SearchSettings.sourcePriorityOrder` must derive from the same descriptor construction used by the pipeline.
- Musixmatch is included only when its token exists.
- Manual searches must not include album metadata in this pass.
- Synthetic local names are not part of remote source-priority preferences.

## Acceptance criteria

- Lirico builds against the intended local LyricsKit API for this work.
- Provider construction uses the current service/descriptors API rather than the removed old API.
- The Source preferences list and emitted remote candidate source names are canonicalized from one shared source list.
- Automatic request construction has a path to include album metadata; manual request construction does not.

## Risks or ambiguity

- Xcode/SPM resolution drift can make the app compile against a different LyricsKit than the code assumes.
- If source-list derivation is split across multiple places, later ranking work will reintroduce naming mismatches.