# SR-02 — LRCLIB exact+broad lookup with dedupe and partial-failure behavior

## Goal

Improve LRCLIB precision by adding the exact `/api/get` path alongside the existing `/api/search` path, while keeping broad search and partial-result behavior intact.

## Depends on / blocks

- **Depends on:** `SR-01`
- **Blocks:** `SR-08`

## Scope

- For title+artist searches with title, artist, album, and duration available, run LRCLIB exact lookup alongside broad search.
- Keep `/api/search` for all existing title+artist and keyword searches.
- Deduplicate LRCLIB results by LRCLIB id/service token before yielding.
- Prefer exact-path metadata/source-trace ties when `/api/get` and `/api/search` produce the same item.
- Treat one-path failure plus one-path success as partial success, not provider failure.
- Add/update LRCLIB tests for URL construction, dual-path behavior, dedupe, and partial-failure semantics.

## Out of scope

- Lirico setting of album metadata on requests.
- LyricsKit group event stream work.
- App-level ranking/evaluation.

## Likely touchpoints

- `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Provider/Services/LRCLIB/LRCLIB.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Sources/LyricsService/Model/LRCLIB/LRCLIBResponse.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Providers/LRCLIBProviderTests.swift`
- `/Users/f/Core/dev/projects/LyricsKit/Tests/LyricsKitTests/Fixtures/LRCLIB/`

## Constraints and decisions to honor

Primary references:
- `../search-ranking-overhaul.md` — **Cross-repo dependency plan**, **LRCLIB lookup rules**, **Resolved decisions**
- `../phases.md` — **Phase 1**

Must honor:
- `/api/search` remains in place for safety and alternatives.
- `/api/get` should not block `/api/search` if concurrency is practical.
- Deduplication is by LRCLIB id/service token.
- LRCLIB is failed only when all attempted paths fail before yielding usable candidates.

## Acceptance criteria

- Keyword requests still use `/api/search` only.
- Complete title+artist+album+duration requests trigger both broad and exact LRCLIB paths.
- Duplicate exact/broad LRCLIB items are emitted once.
- If one LRCLIB path fails and the other succeeds, usable results still arrive.
- Tests cover dual-path requests, dedupe, and failure semantics.

## Risks or ambiguity

- Avoid accidentally changing existing non-LRCLIB provider behavior.
- Be explicit about which item wins when exact and broad results differ only in metadata completeness.