# Search Ranking Overhaul — Story Index

Source of truth:
- `../search-ranking-overhaul.md`
- `../phases.md`

Story sizing: **medium PRs per phase sub-area**.

## Dependency graph

```text
SR-01 -> SR-02
SR-01 -> SR-03
SR-03 -> SR-04
SR-03 -> SR-05
SR-04 -> SR-05
SR-05 -> SR-06
SR-05 -> SR-07
SR-02 -> SR-08
SR-06 -> SR-08
SR-07 -> SR-08
```

## Recommended implementation order

1. `SR-01` — LyricsKit provider events, descriptors, and request album contract
2. `SR-02` + `SR-03` in parallel
3. `SR-04`
4. `SR-05`
5. `SR-06` + `SR-07` in parallel
6. `SR-08`

## Critical serial path

`SR-01 -> SR-03 -> SR-04 -> SR-05 -> SR-07 -> SR-08`

Why:
- `SR-01` establishes the shared cross-repo contracts.
- `SR-03` gets LyricsX onto the new dependency/source substrate.
- `SR-04` and `SR-05` establish the evaluated pipeline consumed by both branches.
- `SR-07` carries the highest-risk correctness and persistence/export behavior.
- `SR-08` closes with hardening and cleanup.

## Parallel branches

After `SR-01`:
- `SR-02` and `SR-03` can run in parallel.

After `SR-05`:
- `SR-06` manual-search branch
- `SR-07` automatic-search branch

## Stories

- `SR-01` — [LyricsKit provider events, descriptors, and request album contract](./SR-01-provider-events-and-request-album-contract.md)
- `SR-02` — [LRCLIB exact+broad lookup with dedupe and partial-failure behavior](./SR-02-lrclib-exact-broad-lookup-and-dedupe.md)
- `SR-03` — [LyricsX local LyricsKit integration and canonical source list](./SR-03-lyricsx-local-lyricskit-integration-and-canonical-sources.md)
- `SR-04` — [Pure evaluator/ranker core in LyricsXFoundation](./SR-04-evaluator-ranker-core.md)
- `SR-05` — [Evaluated pipeline events, ranking config, and strict-search removal](./SR-05-evaluated-pipeline-and-strict-search-removal.md)
- `SR-06` — [Manual search overhaul on top of evaluated candidates](./SR-06-manual-search-overhaul.md)
- `SR-07` — [Automatic search overhaul with deadline and local-upgrade policy](./SR-07-automatic-search-overhaul.md)
- `SR-08` — [Hardening, tuning, and cleanup](./SR-08-hardening-tuning-and-cleanup.md)
