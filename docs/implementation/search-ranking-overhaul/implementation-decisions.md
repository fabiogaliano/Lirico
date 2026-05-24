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
