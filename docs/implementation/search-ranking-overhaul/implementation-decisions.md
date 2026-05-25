# Search Ranking Overhaul — Implementation Decision Log

This log captures **implementation-time decisions** that were not already explicitly
resolved in the plan/phases/stories. The orchestrator owns and normalizes this file;
implementation subagents may propose entries.

See `search-ranking-overhaul.md` (**Resolved decisions**) for decisions already fixed by
the plan — those are not repeated here. Only deviations, newly-forced choices, and
implementation-discovered ambiguities belong below.

---

<!-- New entries appended below in DEC-00X order. -->

## DEC-001 — `events(for:)` ordinal source-name fallback for the legacy initializer

- **Date:** 2026-05-25
- **Story:** SR-01
- **Status:** accepted
- **Problem:** `LyricsProviders.Group` keeps two initializers: the legacy `init(providers:plugins:)` and the new `init(descriptors:plugins:)`. Only the descriptor path knows canonical source names. `events(for:)` could be called on a group built either way.
- **Decision:** When `descriptors` is empty (legacy init), `events(for:)` emits synthetic ordinal source names (`"Provider0"`, `"Provider1"`, …) instead of crashing or returning an empty stream. The descriptor init echoes canonical names verbatim.
- **Why:** Graceful degradation keeps `events(for:)` usable for tests/legacy callers without a hard precondition, while the descriptor path remains the single source of truth for canonical names.
- **Impact:** **SR-03 MUST construct the LyricsX provider group via `init(descriptors:plugins:)` before consuming `events(for:)` source names.** If SR-03 consumes events from a legacy-initialized group, source-priority logic in SR-05/SR-07 would silently compare against ordinal names and break. No code compiling today breaks (purely additive).
- **Alternatives considered:** `precondition`/`fatalError` on legacy init + events (too aggressive for a compatibility window); making `events(for:)` unavailable on legacy groups (would complicate the type).
- **Follow-up:** SR-03 to migrate construction to the descriptor initializer and verify canonical source names flow into `lyrics.metadata.service` / `sourcePriorityOrder`.

## DEC-002 — `lyrics(for:)` and `events(for:)` are independent paths sharing a fan-out helper

- **Date:** 2026-05-25
- **Story:** SR-01
- **Status:** accepted
- **Problem:** The plan describes `lyrics(for:)` as a "candidate-only convenience wrapper" over the event substrate. Reimplementing `lyrics(for:)` on top of `events(for:)` risked changing existing callers' ordering/cancellation/error model (events are non-throwing; `lyrics(for:)` is an `AsyncThrowingStream`).
- **Decision:** Keep `lyrics(for:)` as its own unchanged code path. `events(for:)` mirrors its plugin-expansion structure (run original-request providers immediately + concurrently expand plugins and run derived-request providers) and both share a single `runProviders(_:for:continuation:)` fan-out helper so per-request provider iteration cannot drift.
- **Why:** Preserves exact legacy behavior for `lyrics(for:)` callers while keeping the two paths structurally aligned via the shared helper.
- **Impact:** `Group.swift`. Future behavioral changes to one path are not automatically inherited by the other; the shared helper covers per-request fan-out only, not the top-level orchestration (original-vs-plugin task structure is duplicated and must be kept in sync by hand).
- **Alternatives considered:** Reimplement `lyrics(for:)` over `events(for:)` (rejected: behavioral-drift risk for existing callers).
- **Follow-up:** none for SR-01. Revisit if a future story needs `lyrics(for:)` to gain event-only behavior.

## DEC-003 — `completed` suppression relies on a post-taskgroup `Task.isCancelled` check

- **Date:** 2026-05-25
- **Story:** SR-01
- **Status:** accepted
- **Problem:** `events(for:)` suppresses `.completed` when the wrapping task is cancelled, checked after `withTaskGroup` returns. A narrow race exists: if a consumer breaks the stream in the window between all providers finishing and the `isCancelled` check, `.completed` can be suppressed even though work finished normally.
- **Decision:** Accept this as a known, benign limitation. The only reachable failure direction is "false cancelled" (never "spurious completed after a real cancel"), and it can only occur once the consumer has already stopped iterating, so the suppressed `.completed` would not be observed anyway.
- **Why:** The safe failure direction plus the unobservable-by-construction window make a heavier synchronization mechanism unjustified for this pass.
- **Impact:** `Group.swift` cancellation path. Relevant context for SR-05 (manual 30s timeout) and SR-07 (automatic 15s deadline), which key off the presence/absence of `completed`.
- **Alternatives considered:** Explicit completion flag guarded by a lock/actor (added complexity for an unobservable race).
- **Follow-up:** Revisit only if SR-05/SR-07 cancellation/deadline handling shows a real defect traceable to this window.

## DEC-004 — LyricsX builds against local LyricsKit by default (temporary build scaffolding)

- **Date:** 2026-05-25
- **Story:** SR-03
- **Status:** accepted
- **Problem:** SR-03's code requires the SR-01 `LyricsProviders.Group(descriptors:)` / `ProviderDescriptor` API, which exists only in the local LyricsKit checkout (`/Users/f/Core/dev/projects/LyricsKit`, commit `ba93db6`), not in the remote-pinned LyricsKit `1.9.0`. The existing `LyricsXPackage/Package.swift` local override was opt-in (`isEnabled: useLocalDependency`, default off), so a normal build would fail against the remote API. The plan (Phase 0.5) sanctioned either default-on local or a documented env toggle.
- **Decision:** Added a dedicated `useLocalLyricsKit` flag, **default-on**, expressed as the negation of an opt-out env var: `useLocalLyricsKit = !envEnable("LYRICSX_USE_REMOTE_LYRICSKIT", default: false)`. The LyricsKit dependency entry now gates on this flag. MusicPlayer's dependency is untouched (still the opt-in `LYRICSX_USE_LOCAL_DEPENDENCY`). Escape hatch: `LYRICSX_USE_REMOTE_LYRICSKIT=1` restores the remote package. The existing `isClonedDependency` guard still forces remote when built as a cloned dependency.
- **Why:** Default-on local is required for every contributor to build the overhaul branch without per-machine env setup; a negated opt-out flag keeps the default correct while preserving a CI/release escape hatch. Local path overrides are intentionally not pinned in `Package.resolved`.
- **Impact:** `LyricsXPackage/Package.swift`. A clone WITHOUT the sibling `../../LyricsKit` checkout falls back to remote `1.9.0` and will fail to build SR-03+ code (expected during this overhaul). This is the inverse default-risk of the old opt-in flag.
- **Alternatives considered:** Keep opt-in + document `LYRICSX_USE_LOCAL_DEPENDENCY=1` (rejected: easy to forget, breaks default build for the overhaul branch); vendor the LyricsKit changes (out of scope).
- **Follow-up:** **Must reconcile before merge/release.** When SR-01/SR-02 LyricsKit changes are published and the remote pin is bumped, revert `useLocalLyricsKit` to the opt-in toggle (or remove it) and update `Package.resolved`. Track in SR-08 cleanup.

## DEC-005 — LRCLIB dual-path via a LRCLIB-only `lyrics(for:)` override

- **Date:** 2026-05-25
- **Story:** SR-02
- **Status:** accepted
- **Problem:** The exact `/api/get` signature lookup must run concurrently with the existing `/api/search` broad path, but the shared `_LyricsProvider.lyrics(for:)` default calls `search(for:)` then awaits per-item fetches serially. Adding a second concurrent path without restructuring the provider protocol required a provider-specific entry point.
- **Decision:** Override `lyrics(for:)` on the concrete `LyricsProviders.LRCLIB` type only. It starts both paths via `async let` (broad + exact), dedupes by LRCLIB `id` (exact wins ties by being inserted first), then reuses the base's per-item fetch fan-out. The shared `_LyricsProvider` contract and all other providers are untouched. Because LRCLIB is stored in `Group` as a `LyricsProvider` existential, both `Group.lyrics(for:)` and SR-01's `Group.events(for:)` dispatch to this override, so dual-path applies uniformly.
- **Why:** A LRCLIB-only override is the smallest change that delivers concurrent dual-path without forcing every provider to adopt a new multi-path contract.
- **Impact:** `LRCLIB.swift`. Also widened `LyricsProviderLog` from `private` to `internal` (module-scoped, no behavior change) so the override logs per-item fetch failures identically to the base. Partial-failure semantics: one-path-fail + one-path-success yields results without throwing; an empty-but-successful broad response is NOT a failure (no throw), per the plan's "failed only when all attempted paths fail before yielding usable candidates"; the provider throws only when both paths error before yielding. Exact-lookup duration is sent rounded to whole seconds (`%.0f`).
- **Alternatives considered:** Make `gatherTokens` the new `search(for:)` contract for all providers (rejected: forces unrelated providers to change); serialize the two paths (rejected: violates the non-blocking concurrency rule).
- **Follow-up:** The token-level `fromExactLookup` flag is set but not surfaced into `Lyrics.metadata`. If source-trace diagnostics are wanted, surface it in SR-08; not required by SR-02's contract.

## DEC-006 — Evaluator/ranker concrete thresholds and ordering mechanics

- **Date:** 2026-05-25
- **Story:** SR-04
- **Status:** accepted
- **Problem:** The plan fixed score *bands* and the karaoke *window concept* but not the exact within-tier ordering mechanics, band edges for primary-vs-featured artists, or which words count as title "version markers." Initial implementation had real bugs here (caught by review).
- **Decision:**
  - **Karaoke preference:** a karaoke candidate whose `gap = bestLineSyncedScore - score` satisfies `0 <= gap <= karaokePreferenceWindow` is promoted to an effective sort score of `bestLineSyncedScore + 0.001`, so it floats just above the line-synced candidate it competes with. Match tier remains the dominant sort key, so promotion never crosses tiers. (An earlier `+0.5` flat bonus was inert for any realistic gap — fixed.)
  - **Score bands non-overlapping for artist primacy:** exact-primary artist clamps to `96...100`, exact-non-primary (featured) to `92...95`. Primary floor (96) > non-primary ceiling (95) guarantees an exact-primary match always outranks an exact-featured match within `.exactTitleArtist`, regardless of duration/album tiebreakers. (Earlier overlapping `95...100`/`92...97` let a featured match win — fixed.) Other bands: strong `88...94`, loose `75...87`.
  - **`rankedCandidates` output (corrected — see DEC-008):** loose-fallback rows appear ONLY when the set contains no `.normal` candidate (loose suppressed when any normal exists); `.rejected` is fully excluded; `.unlikely` candidates ARE included, appended AFTER the visible normal/loose section (`return sorted + sortedUnlikely`), so consumers can split likely-vs-unlikely from one call. `bestCandidate` never selects `.unlikely`/`.rejected`. Collection-aware via set membership.
  - **Version markers (core-title stripping)** are restricted to genuine format/variant descriptors (acoustic, live, remix, remaster, deluxe, instrumental, edit, version, mix, demo, mono, stereo, …). Collaboration/preposition words (`and`, `with`, `feat`, `ft`, `featuring`) were REMOVED — they appear in real titles (`you and i` vs `you and me`) and were collapsing distinct songs. Collaboration separators remain handled in artist-relation splitting only.
  - **Exact-title + clearly-wrong-artist → `.unlikely`** (tier `.rejected`, reason `.artistMismatch`), NOT `.rejected`. Hidden by default but reachable via the manual unlikely toggle; ranked below normal and never chosen by `bestCandidate` when a normal exists, and automatic loose-fallback applies only to `.looseFallback` (not `.unlikely`), so the wrong-song invariant holds. `.rejected` is reserved for zero-title-overlap.
- **Why:** These are the smallest deterministic mechanics that satisfy the plan's tier-before-score, karaoke-window, primary-over-featured, and "never collapse arbitrary titles" requirements while keeping the model pure and testable.
- **Impact:** `LyricsCandidateEvaluator.swift`, `LyricsCandidateRanker.swift`. **`EvaluatedLyricsCandidate` is `Identifiable, Hashable` but NOT `Sendable`** (because LyricsKit `Lyrics` is a non-Sendable `final class`; the plan's struct shape also omits Sendable). **SR-05 must apply `@preconcurrency import LyricsKit` (or equivalent) when carrying `EvaluatedLyricsCandidate` as an `AsyncStream<LyricsSearchEvent>` payload.**
- **Alternatives considered:** Storing `artistRelation`/`isExactPrimary` on the evaluation and sorting on it (rejected for now in favor of non-overlapping bands — more surgical); per-tier `bestLineSyncedScore` (current impl uses the best within the visible same-partition set, which is correct because `rankedCandidates` never mixes normal/loose in one sort).
- **Follow-up (SR-08 hardening):** complete the full 20-case evaluator/ranker test matrix; remove dead multi-word entries in `versionMarkers` (`radio edit`, `original mix`, etc. — unreachable since stripping is per-token); optionally surface artist-relation explicitly if featured-artist edge cases need finer control.

## DEC-007 — SR-05 evaluated-pipeline surface and the transient automatic-search no-gate window

- **Date:** 2026-05-25
- **Story:** SR-05
- **Status:** accepted
- **Problem:** Strict-search removal lands in SR-05 (shared pipeline) per the plan, but the automatic (`LyricsSession`) and manual (`SearchLyricsViewModel`) callers are NOT migrated to the evaluator until SR-07/SR-06. Removing the `Lyrics.isMatched()` strict gate while those callers still use the legacy `candidates(for:)` + `LyricsSelector.hasHigherPriority` path leaves a window with no correctness filter.
- **Decision:**
  - Added app-level `LyricsSearchEvent` (5 cases) and `LyricsSearchPipeline.events(for:mode:requestedDuration:requestedAlbum:) -> AsyncStream<LyricsSearchEvent>`. It consumes the descriptor-built `LyricsProviders.Group.events(for:)` (SR-01), stamps `metadata.service = source` BEFORE preparation+evaluation, evaluates via `LyricsCandidateEvaluator`, assigns `arrivalIndex` per app-stream candidate yield, and emits ALL evaluations (`.unlikely`/`.rejected` included). Non-throwing; never synthesizes `.completed`; cancellation chains app-stream → inner Task → `Group.events` → provider task group (verified).
  - `LyricsSearchEvent` lives in `LyricsSearchPipeline.swift` (small, tightly coupled to its sole producer). `providerGroup` narrowed to concrete `LyricsProviders.Group` (existential `LyricsProvider` lacks `events(for:)`). Evaluator instantiated per call (pure/stateless). `@preconcurrency import LyricsKit` carries non-Sendable `EvaluatedLyricsCandidate` (DEC-006) with zero warnings.
  - Removed strict-search fully: `SearchSettings.strictSearchEnabled`, the `UserDefaultsKeys` entry, the General-prefs toggle, and the `isMatched()` filter. `candidates(for:strict:)` → `candidates(for:)`; the two callers updated to compile, NOT migrated to `events(...)`.
  - **KEPT** `LyricsSelector.hasHigherPriority`/`insert`/`makeCollector`/`LyricsCollector` — automatic search still uses them until SR-07. Removing them now would strand the unmigrated caller.
- **Why:** The evaluated pipeline must exist and strict-search must go before the consumer branches diverge; keeping the legacy selector alive avoids breaking the not-yet-migrated automatic path.
- **Impact:** `LyricsSearchPipeline.swift`, `SearchSettings.swift`, `UserDefaultsKeys.swift`, `GeneralPreferencesView.swift`, `LyricsSession.swift`, `SearchLyricsViewModel.swift`. **TRANSIENT: between SR-05 and SR-07, automatic search has no `isMatched` gate and is not yet on the evaluator — slightly more permissive. This is plan-sanctioned and MUST be closed by SR-07** (which wires the evaluator/ranker into automatic acceptance and removes the legacy selector usage).
- **Alternatives considered:** Keep strict until SR-07 (rejected: contradicts SR-05 scope and phases.md "strict-search removal belongs with the shared evaluated pipeline"); migrate callers now (rejected: that IS SR-06/SR-07, would collapse stories).
- **Follow-up:** SR-07 closes the transient window and retires the legacy `LyricsSelector` pairwise APIs + `candidates(for:)` compatibility path once both consumers are on `events(...)`. SR-08: remove the orphaned `"Strict search"` entry in `Localizable.xcstrings` (toggle already gone).

## DEC-008 — Manual-search state model and the clarified `rankedCandidates` contract

- **Date:** 2026-05-25
- **Story:** SR-06
- **Status:** accepted
- **Problem:** The manual window needed a state model that consumes the SR-05 `events(...)` stream, partitions results (likely/unlikely/rejected), drives status + button labels, and never reaches an illegal state (Apply/preview on a hidden row). It also surfaced that the SR-04 `LyricsCandidateRanker.rankedCandidates` contract was mis-described in DEC-006.
- **Decision:**
  - **Ranker contract clarified (authoritative):** `rankedCandidates(...)` returns `sortedVisible + sortedUnlikely` where `sortedVisible` is the ranked normal set (or loose set only when no normal exists); `.rejected` is fully excluded; `.unlikely` rows ARE present, appended at the end. Consumers split likely vs unlikely by visibility. (DEC-006's earlier "excludes `.unlikely`" wording was wrong and has been corrected in place.) The ranker was NOT changed — this documents its real, tested behavior, which SR-06 depends on.
  - **VM state model:** store the full `allCandidates: [EvaluatedLyricsCandidate]` (incl. unlikely + rejected). Derive everything else: `likelyRows` = ranker output minus `.unlikely`; `unlikelyRows` = ranker output kept to `.unlikely`; `unlikelyCount` reads directly from `allCandidates` (canonical). `visibleRows` = likely + (unlikely when toggle on). `canApply` requires the selected id ∈ `visibleRows` AND a current track, so a hidden row can never be applied. Selection/preview/artwork are cleared on new search / Search Again / unlikely-toggle-off-while-unlikely-selected.
  - **Single source of truth:** `searchStatus` drives both the status line and `buttonLabel` (Search/Cancel/Search Again). `fieldsChangedSinceSearch` compares trimmed field values against a snapshot taken at search launch (trailing-space edits don't count).
  - **Timeout/cancellation:** 30s timeout via `withTaskGroup` racing the stream consumer vs a sleep sentinel; first to finish cancels the other; cancelling the task tears down the `events(...)` stream (chained per DEC-007). Partial results preserved on cancel/timeout/failure.
  - **UI:** mic indicator uses SF Symbol `mic.fill` (not emoji); source column shows canonical `lyrics.metadata.service`; `SearchStatus` enum lives at file scope in `SearchLyricsViewModel.swift` (UI-state concern, not package).
  - **SR-07 boundary respected:** `apply()` calls `session.select(...)` with today's semantics only; no automatic-cancellation coupling; `LyricsSelector` APIs preserved.
- **Why:** Deriving views from one stored set + visibility makes illegal states unrepresentable; reading `unlikelyCount` from `allCandidates` is robust regardless of ranker output details.
- **Impact:** `SearchLyricsViewModel.swift`, `SearchLyricsView.swift` (full rewrites). Build clean, 48 pkg tests pass.
- **Alternatives considered:** Sourcing `unlikelyRows` from `allCandidates` instead of ranker output (equivalent; current approach reuses the ranker's ordering for unlikely rows too).
- **Follow-up (SR-08, non-blocking nits from review):** (1) `likelyRows`/`unlikelyRows` each call the ranker → two ranker passes per render; cache one `ranked` result. (2) remove the misleading `_ = rejected` suppression in `updateFoundStatus`. (3) pre-existing UX gap (not an SR-06 regression): when a mid-stream-arriving normal candidate suppresses a previously-visible loose row that is currently selected, `selectionID`/`preview` aren't proactively refreshed (Apply is correctly blocked, but preview shows stale content until selection changes) — consider invalidating selection when the visible set changes.
