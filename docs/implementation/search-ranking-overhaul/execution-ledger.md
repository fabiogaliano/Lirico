# Search Ranking Overhaul — Execution Ledger

Lightweight orchestration state. One row per story. Full implementation detail lives in
diffs/files, not here.

Status values: `not started` / `in progress` / `implemented` / `under review` /
`fixes needed` / `validated` / `committed` / `done`.

## Waves

```
Wave 1: SR-01
Wave 2: SR-02 || SR-03
Wave 3: SR-04
Wave 4: SR-05
Wave 5: SR-06 -> SR-07   (sequenced; carve a seam first if forcing parallel)
Wave 6: SR-08
```

Critical path: SR-01 -> SR-03 -> SR-04 -> SR-05 -> SR-07 -> SR-08

## Stories

| Story | Repo | Status | Blockers | Commit | Decisions | Notes |
|-------|------|--------|----------|--------|-----------|-------|
| SR-01 | LyricsKit | committed | none | LyricsKit ba93db6 | DEC-001, DEC-002, DEC-003 | events+descriptors+album; review caught & fixed plugin-event gap; 57 tests pass |
| SR-02 | LyricsKit | committed | SR-01 | LyricsKit 7551897 | DEC-005 | LRCLIB exact+broad lookup, dedupe, partial-failure; review APPROVED; 63 tests pass |
| SR-03 | LyricsX | committed | SR-01 | LyricsX 35868700 | DEC-004 | local LyricsKit integration + canonical sources; review caught & fixed Musixmatch source-list regression; build clean |
| SR-04 | LyricsX (pkg) | committed | SR-03 | LyricsX a3ea11d8 | DEC-006 | pure evaluator/ranker core; review caught 4 ranking bugs (karaoke window inert, band overlap, loose leak, marker over-broad) all fixed; 48 tests pass |
| SR-05 | LyricsX | not started | SR-03, SR-04 | — | — | evaluated pipeline + strict-search removal |
| SR-06 | LyricsX | not started | SR-05 | — | — | manual search overhaul |
| SR-07 | LyricsX | not started | SR-05 (+SR-06 merge order) | — | — | automatic search overhaul |
| SR-08 | both | not started | SR-02, SR-06, SR-07 | — | — | hardening, tuning, cleanup |
