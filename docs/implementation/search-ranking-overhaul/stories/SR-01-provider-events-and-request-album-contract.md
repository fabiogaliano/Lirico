# SR-01 — LyricsKit provider events, descriptors, and request album contract

## Goal

Add the shared LyricsKit contracts that downstream LyricsX work depends on:
- provider descriptors with canonical source names,
- a non-throwing group event stream,
- the shared request album metadata convention.

## Depends on / blocks

- **Depends on:** none
- **Blocks:** `SR-02`, `SR-03`, `SR-05`

## Scope

- Add `LyricsProviders.ProviderDescriptor`.
- Add `LyricsProviders.ProviderEvent` with started/candidate/finished/failed/completed cases.
- Add `LyricsProviders.Group.events(for:) -> AsyncStream<...>`.
- Preserve `lyrics(for:)` as a candidate-only compatibility wrapper over the new event substrate.
- Add `LyricsSearchRequest.UserInfoKey.albumName` and `LyricsSearchRequest.albumName`.
- Add or update LyricsKit tests for event emission, failure-as-value behavior, and cancellation semantics.

## Out of scope

- LRCLIB `/api/get` exact lookup logic.
- LyricsX provider-construction migration.
- App-level evaluation/ranking.
- Manual or automatic LyricsX behavior changes.

## Likely touchpoints

- `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Group.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Service.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/LyricsSearchRequest.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/GroupProviderTests.swift`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Cross-repo dependency plan**, **Provider feedback**, **Resolved decisions**
- `../phases.md` — **Shared-contract gates**, **Phase 1**

Must honor:
- Provider events are **group-level only** in this pass.
- `Group.events(for:)` is **non-throwing**.
- Provider failures are emitted as **event values**, not thrown stream errors.
- `completed` is emitted only on normal completion, never after cancellation.
- Event `source` must echo the descriptor `source` exactly.
- Plugin-derived searches must stay traceable via the request on start/finish/failure events.

## Acceptance criteria

- `LyricsProviders.Group` can emit provider lifecycle events without terminating the whole stream when one provider fails.
- `lyrics(for:)` still works for existing callers.
- Request album metadata is available through a first-class shared API on `LyricsSearchRequest`.
- Tests cover:
  - started/candidate/finished/completed emission,
  - providerFailed without cancelling sibling providers,
  - no `completed` after cancellation.

## Risks or ambiguity

- The compatibility wrapper must not subtly change current provider ordering/cancellation behavior.
- Descriptor ownership needs to stay the single source of truth for source names; avoid duplicate naming paths.