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
| SR-05 | LyricsX | committed | SR-03, SR-04 | LyricsX 82bfba3a | DEC-007 | evaluated pipeline events + ranking config + strict removed; review APPROVE w/ nits; build clean, 48 pkg tests; cancellation chains fully; transient no-gate window for auto search until SR-07 |
| SR-06 | LyricsX | committed | SR-05 | LyricsX 94876776 | DEC-008 | manual search overhaul (VM+View rewrite); review APPROVE w/ nits; suspected unlikely bug was false; corrected DEC-006 ranker-contract wording; build clean, 48 pkg tests |
| SR-07 | LyricsX | committed | SR-05, SR-06 | LyricsX 3b2bbeaa | DEC-009 (closes DEC-007) | automatic overhaul; review APPROVE; caught+fixed karaoke gap>=0 upgrade bug + importLyrics override gap; build clean, 48 pkg tests; SR-08 follow-ups: lyricsDisplay threading, dead-code removal |
| SR-08 | both | committed | SR-02, SR-06, SR-07 | LyricsKit 4ffc3cc / LyricsX bf451da8 | DEC-010 | hardening done; LyricsKit 65 tests (8 cases), LyricsXFoundation 68 tests (20 cases); fixed album-tiebreaker defect; extracted local-upgrade policy; dead code removed; both reviews APPROVE; build clean. EXCLUDED (known items): lyricsDisplay threading (DEC-009#1), useLocalLyricsKit revert (DEC-004) |
