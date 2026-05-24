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
| SR-01 | LyricsKit | validated | none | pending commit | DEC-001, DEC-002, DEC-003 | events+descriptors+album; review caught & fixed plugin-event gap; 57 tests pass |
| SR-02 | LyricsKit | not started | SR-01 | — | — | LRCLIB exact+broad lookup, dedupe |
| SR-03 | LyricsX | not started | SR-01 | — | — | local LyricsKit integration + canonical sources |
| SR-04 | LyricsX (pkg) | not started | SR-03 | — | — | pure evaluator/ranker core |
| SR-05 | LyricsX | not started | SR-03, SR-04 | — | — | evaluated pipeline + strict-search removal |
| SR-06 | LyricsX | not started | SR-05 | — | — | manual search overhaul |
| SR-07 | LyricsX | not started | SR-05 (+SR-06 merge order) | — | — | automatic search overhaul |
| SR-08 | both | not started | SR-02, SR-06, SR-07 | — | — | hardening, tuning, cleanup |
