# Search Ranking Overhaul — Implementation Phases

Derived from `docs/implementation/search-ranking-overhaul.md` plus the current Lirico and local LyricsKit codebase. This breakdown is dependency-driven, not section-driven.

## Shared-contract gates before parallel work

These contracts should land before downstream work splits into parallel branches.

1. **Canonical source identity**
   - `LyricsProviders.ProviderDescriptor.source` becomes the single source name used by LyricsKit events, `lyrics.metadata.service`, `availableLyricsSources`, source-priority settings, and the manual Source column.
   - Why first: phase 2 ranking and both UI/session consumers depend on stable source names.

2. **Request-context contract**
   - `LyricsSearchRequest.UserInfoKey.albumName` / `albumName` must exist in LyricsKit.
   - Automatic current-track searches set album when available; manual searches do not.
   - Why first: LRCLIB exact lookup and album-aware evaluation both depend on it.

3. **Evaluated-candidate contract**
   - `LyricsSearchMode`, `LyricsCandidateEvaluation`, `EvaluatedLyricsCandidate`, `LyricsCandidateRankingConfiguration`, `LyricsSyncKind`, and app-level `LyricsSearchEvent` need stable shapes before the manual and automatic branches diverge.
   - Why first: both branches consume the same evaluated stream and ranking rules.

## Phase 1 — Shared contracts and search substrate

- **Goal:** Establish the cross-repo search contracts and provider/source plumbing everything else builds on.
- **Why it exists:** The app cannot safely rank, report status, or honor source priority until LyricsKit owns canonical source names and exposes provider lifecycle events.
- **Inputs / dependencies:**
  - Plan decisions around provider events, descriptors, album metadata, LRCLIB exact lookup.
  - Current code in `LyricsKit/Sources/LyricsService/Provider/Group.swift`, `Service.swift`, `LyricsSearchRequest.swift`, `Services/LRCLIB/LRCLIB.swift`.
  - Current Lirico provider setup in `Lirico/Component/LyricsSearchPipeline.swift`, `LyricsSelector.swift`, `SearchSettings.swift`, `AppContainer.swift`, `SourcePreferencesView.swift`, `LiricoPackage/Package.swift`.
- **Outputs:**
  - LyricsKit `ProviderDescriptor` + non-throwing `Group.events(for:)`.
  - `lyrics(for:)` preserved as a compatibility wrapper.
  - `LyricsSearchRequest.albumName` convention.
  - LRCLIB `/api/get` exact lookup alongside `/api/search`, with dedupe and partial-failure behavior.
  - Lirico provider construction migrated to descriptor / `ServiceID`-based APIs.
  - Canonical source list derived from the same descriptor construction used by the pipeline.
- **Key touchpoints:**
  - `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Group.swift`
  - `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Service.swift`
  - `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/LyricsSearchRequest.swift`
  - `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Services/LRCLIB/LRCLIB.swift`
  - `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/GroupProviderTests.swift`
  - `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/LRCLIBProviderTests.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSelector.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Preferences/SourcePreferencesView.swift`
  - `/Users/f/Core/dev/projects/Lirico/LiricoPackage/Package.swift`
- **Risks:**
  - Source-name drift between provider events, preferences, and UI.
  - Cross-repo API mismatch while Lirico still points at the resolved remote package.
  - Regressing current search behavior while compatibility wrappers still exist.
- **Parallelizable within the phase:**
  - LyricsKit event API + tests.
  - LRCLIB exact-lookup path + dedupe tests.
  - Lirico provider-construction/source-list migration **after** the descriptor/source contract is fixed.
- **Exit criteria:**
  - Lirico builds against the local LyricsKit API for this work.
  - Provider events, canonical source names, and album metadata are available.
  - Existing caller flows can still fetch candidates through a compatibility path.

## Phase 2 — Evaluated candidate core and pipeline mapping

- **Goal:** Introduce the shared evaluator/ranker and make the pipeline emit evaluated app-level search events.
- **Why it exists:** Manual and automatic search cannot diverge into separate implementations; both need the same candidate semantics before any UI or session behavior changes.
- **Inputs / dependencies:**
  - Phase 1 source identity, event stream, and request-context contracts.
  - Existing preparation path in `LyricsSearchPipeline`.
  - Current `Lyrics.quality` / `Lyrics.isMatched()` behavior in LyricsKit and current `LyricsSelector` ordering logic.
- **Outputs:**
  - New `LiricoFoundation/Search/` module for search mode, sync kind, evaluation, evaluator, and ranker.
  - Normalization/tokenization helpers and karaoke detection helpers on `Lyrics`.
  - `SearchSettings.rankingConfiguration` mapper.
  - Non-throwing `LyricsSearchPipeline.events(...)` yielding app-level `LyricsSearchEvent` values with `EvaluatedLyricsCandidate` payloads.
  - `lyrics.metadata.service` canonicalized from provider-event source before preparation/evaluation leaves the pipeline.
  - Strict-search preference and old `strict` / `Lyrics.isMatched()` gating removed once the evaluated path is live.
  - `LyricsSelector` reduced, replaced, or repurposed around ranker-driven behavior instead of source-priority/quality-only comparison.
- **Key touchpoints:**
  - `/Users/f/Core/dev/projects/Lirico/LiricoPackage/Sources/LiricoFoundation/`
  - `/Users/f/Core/dev/projects/Lirico/LiricoPackage/Tests/LiricoFoundationTests/`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSelector.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Preferences/GeneralPreferencesView.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Utility/UserDefaultsKeys.swift`
- **Risks:**
  - Title/artist normalization rules are easy to over-broaden.
  - Set-level rank rules do not fit the current pairwise-only selector model.
  - Removing strict-search too early can strand callers if the evaluated pipeline is incomplete.
- **Parallelizable within the phase:**
  - Evaluator + normalization helpers.
  - Ranker + set-level ordering rules.
  - Pipeline event mapping and compatibility wrapper work.
  - These can overlap **after** the evaluated-candidate contract is fixed.
- **Exit criteria:**
  - Both manual and automatic callers can consume one evaluated event stream.
  - The app no longer relies on `Lyrics.isMatched()` or `Lyrics.quality` as the primary correctness gate.
  - Core package tests exist for enough evaluator/ranker cases to unblock the consumer branches.

## Phase 3 — Manual search branch

- **Goal:** Rebuild manual search around evaluated candidates and event-driven UX.
- **Why it exists:** The manual window is the place where users inspect ranking, fallbacks, karaoke preference, and provider progress directly.
- **Inputs / dependencies:**
  - Phase 2 evaluated pipeline and ranking configuration.
  - Current manual flow in `SearchLyricsViewModel`, `SearchLyricsView`, and `SearchLyricsWindowController`.
- **Outputs:**
  - Title+artist, title-only, and artist-only request construction.
  - View-model storage for evaluated candidates, visible rows, hidden-unlikely count, and rejected diagnostics.
  - Correct title-based loose-fallback suppression and artist-only A–Z ordering.
  - Mic indicator, unlikely-results toggle, and selection clearing rules when rows become hidden.
  - `SearchStatus` model with provider summary, cancel/failure/timeout/no-match states.
  - Search / Cancel / Search Again button behavior and keyboard handling.
  - Apply enabled only for visible rows with a current track; no-track manual search still supports search/preview/drag.
- **Key touchpoints:**
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsViewModel.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsView.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsWindowController.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
- **Risks:**
  - `SearchLyricsViewModel.swift` and `SearchLyricsView.swift` are merge hot spots.
  - Filtered visibility can desync selection, preview, artwork, and Apply enablement.
  - Provider-summary copy and button-state transitions are easy to make inconsistent.
- **Parallelizable within the phase:**
  - Result partitioning/ranking and search-mode request work.
  - Row/toggle rendering.
  - Status/button/timeout behavior.
  - **Shared-contract work inside the phase:** agree the ViewModel state surface first (`LyricsResult` shape, `SearchStatus`, visible/hidden derivation, selection invalidation rules), then parallelize UI work behind it.
- **Exit criteria:**
  - Manual search supports all three modes.
  - Rejected rows never display.
  - Unlikely rows only appear behind the toggle.
  - Provider summary status, cancel, timeout, and Search Again behavior work with partial results preserved.

## Phase 4 — Automatic search branch

- **Goal:** Replace accept-first + `priorityWindow` automatic search with evaluated, deadline-based selection and explicit local-upgrade rules.
- **Why it exists:** Automatic search is what drives `LyricsSession.currentLyrics`, desktop lyrics, persistence, and Apple Music export; it is the highest-risk correctness path.
- **Inputs / dependencies:**
  - Phase 2 evaluated event pipeline.
  - Current `LyricsSession.currentTrackChanged()` flow and `LocalLyricsLoader` behavior.
  - Existing `select(...)`, `clear(...)`, persistence, and export semantics.
- **Outputs:**
  - Event-driven automatic candidate collection in `LyricsSession`.
  - Interim best-candidate display plus final best-candidate finalization.
  - 15-second automatic deadline owned by `LyricsSession`.
  - Local karaoke preservation and local line-synced upgrade policy.
  - Conservative loose-fallback policy.
  - Manual `select(...)` / Apply cancellation boundary so user choice cannot be replaced by later automatic finalization/export.
  - Final-only persistence/export behavior for dirty remote results.
- **Key touchpoints:**
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSession.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LocalLyricsLoader.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSearchPipeline.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Search/SearchLyricsViewModel.swift`
- **Risks:**
  - Race conditions between track changes, manual selection, deadlines, and late provider events.
  - Accidentally exporting/persisting interim results.
  - Overwriting strong local user-provided lyrics with weaker remote results.
- **Parallelizable within the phase:**
  - Local-upgrade acceptance-policy work.
  - Deadline/finalization/export state-machine work.
  - **Shared-contract work inside the phase:** define the automatic acceptance state machine first (`normal` vs. local-upgrade-only behavior, finalization boundary, cancellation rules), then split implementation.
- **Exit criteria:**
  - Automatic search uses evaluator/ranker output instead of source-priority/quality-only selection.
  - No late events update `currentLyrics` after cancellation or deadline.
  - Local karaoke is protected.
  - Manual override wins permanently for the current search.
  - Export/persist happens only for the final automatic result.

## Phase 5 — Hardening, tuning, and cleanup

- **Goal:** Finish coverage, tune thresholds, and remove transition scaffolding.
- **Why it exists:** The branch split leaves cleanup and regression-catching work that should happen only after both consumers are wired.
- **Inputs / dependencies:**
  - Phases 1–4 merged.
- **Outputs:**
  - Full `LiricoFoundation` evaluator/ranker tests.
  - Full LyricsKit provider-event/LRCLIB tests.
  - Threshold tuning against real examples.
  - Removal of obsolete strict-search UI/defaults and any remaining compatibility shims.
  - Cleanup of `priorityWindow` if it no longer serves any real path.
  - Relevant package tests and app build verification.
- **Key touchpoints:**
  - `/Users/f/Core/dev/projects/Lirico/LiricoPackage/Tests/LiricoFoundationTests/`
  - `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/SearchSettings.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Utility/UserDefaultsKeys.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Preferences/GeneralPreferencesView.swift`
  - `/Users/f/Core/dev/projects/Lirico/Lirico/Component/LyricsSelector.swift`
- **Risks:**
  - Regressions only becoming visible after manual and automatic branches merge.
  - Threshold tuning churning behavior without enough fixture coverage.
- **Parallelizable within the phase:**
  - LyricsKit tests.
  - LiricoFoundation tests.
  - Cleanup PRs for dead settings/shims after test coverage is in place.
- **Exit criteria:**
  - Relevant package tests pass.
  - Lirico builds cleanly against the intended LyricsKit dependency.
  - No legacy strict-search path remains active.
  - Final ranking behavior is covered by automated tests instead of only manual verification.

## Critical serial path

Expected critical path:

1. **Phase 1** shared contracts and provider/source plumbing.
2. **Phase 2** evaluated-candidate core and pipeline mapping.
3. **Phase 4** automatic search branch.
4. **Phase 5** hardening and cleanup.

Why this is the serial path:
- Phase 2 cannot start safely without phase 1 contracts.
- Automatic search correctness, persistence, and export all sit behind the evaluated pipeline.
- Final cleanup and full hardening should wait until the highest-risk automatic path is merged.

## Parallelizable branches

After phase 2 lands, the work splits cleanly into two main branches:

- **Branch A:** Phase 3 manual search branch.
- **Branch B:** Phase 4 automatic search branch.

They share ranking rules and the evaluated pipeline, but they mostly diverge into different hot files afterward:
- Manual branch hot files: `SearchLyricsViewModel.swift`, `SearchLyricsView.swift`, `SearchLyricsWindowController.swift`.
- Automatic branch hot files: `LyricsSession.swift`, `LocalLyricsLoader.swift`.

Phase 5 waits for both branches to merge.

## Key ordering corrections from the source plan

- Strict-search removal belongs with the shared evaluated pipeline, not only with manual search.
- Manual feedback/status work depends on the evaluated event stream, but it does **not** need to wait for automatic integration once phase 2 is done.
- Manual UI indicators and unlikely-toggle work are not truly standalone from manual ranking/filtering; they are best treated as sub-branches of one manual-search phase behind a stable ViewModel contract.
