# Search Ranking Overhaul — Story Dependency Map

Source of truth:
- `./search-ranking-overhaul.md`
- `./phases.md`
- `./stories/index.md`
- `./stories/SR-01-provider-events-and-request-album-contract.md`
- `./stories/SR-02-lrclib-exact-broad-lookup-and-dedupe.md`
- `./stories/SR-03-lyricsx-local-lyricskit-integration-and-canonical-sources.md`
- `./stories/SR-04-evaluator-ranker-core.md`
- `./stories/SR-05-evaluated-pipeline-and-strict-search-removal.md`
- `./stories/SR-06-manual-search-overhaul.md`
- `./stories/SR-07-automatic-search-overhaul.md`
- `./stories/SR-08-hardening-tuning-and-cleanup.md`

This map combines:
- explicit story dependencies from the story docs, and
- implicit sequencing pressure from overlapping hot files.

## 1. Story dependency graph (textual DAG)

### Hard dependency edges

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

### Soft merge-order edges from file overlap

These are not semantic prerequisites, but they do affect safe branch parallelism.

```text
SR-06 ~> SR-07   (shared `SearchLyricsViewModel.swift`; SR-07 also touches manual-override behavior)
SR-03 ~> SR-08   (shared `SearchSettings.swift` / `LyricsSelector.swift` cleanup zone)
SR-05 ~> SR-08   (shared strict-search cleanup files)
SR-01 ~> SR-08   (shared LyricsKit provider-test surface)
SR-04 ~> SR-08   (shared LiricoFoundation test surface)
```

Legend:
- `->` = hard dependency
- `~>` = recommended merge order due to overlap / cleanup pressure

## 2. Critical path — longest serial chain

Recommended critical path:

```text
SR-01 -> SR-03 -> SR-04 -> SR-05 -> SR-07 -> SR-08
```

Why this is longest and most constraining:
- `SR-01` establishes the shared LyricsKit contracts.
- `SR-03` moves Lirico onto the dependency/source substrate needed by downstream app work.
- `SR-04` establishes the evaluator/ranker core consumed by the pipeline.
- `SR-05` is the shared evaluated-pipeline migration point for both manual and automatic work.
- `SR-07` carries the highest-risk runtime correctness path: automatic selection, deadline handling, persistence/export, and local-upgrade policy.
- `SR-08` must wait for the real merged behavior to harden and clean up.

## 3. Shared-contract stories that must land first

These are the true gate stories before meaningful parallel work begins.

### First gate: `SR-01`

Shared contracts established here:
- `LyricsProviders.ProviderDescriptor`
- `LyricsProviders.ProviderEvent`
- `LyricsProviders.Group.events(for:)`
- `LyricsSearchRequest.albumName`

Why first:
- `SR-02` depends on the album/request contract.
- `SR-03` depends on canonical source naming and the new LyricsKit surface.
- `SR-05` ultimately depends on provider-event availability.

### Second gate: `SR-03`

Shared integration substrate established here:
- Lirico uses the intended local LyricsKit API.
- Provider construction moves to the descriptor / `ServiceID` path.
- Canonical source list and source-priority normalization come from one construction path.

Why next:
- `SR-04` and `SR-05` both assume Lirico is on the correct dependency/source substrate.

### Third gate: `SR-05`

Shared evaluated-consumer contract established here:
- app-level `LyricsSearchEvent`
- evaluated pipeline output
- `SearchSettings.rankingConfiguration`
- strict-search removal from the shared pipeline path

Why this is the final pre-branch gate:
- both `SR-06` and `SR-07` consume this same evaluated stream and ranking surface.

## 4. Hot files / merge-risk zones

Based on the story touchpoints, these are the highest-conflict files and directories.

### Highest-risk files

- `Lirico/Component/SearchSettings.swift`
  - touched by `SR-03`, `SR-05`, `SR-06`, `SR-07`, `SR-08`
  - risk: source-list normalization, ranking config, legacy-setting cleanup, branch drift

- `Lirico/Component/LyricsSearchPipeline.swift`
  - touched by `SR-03`, `SR-05`, `SR-06`, `SR-07`
  - risk: provider construction, event mapping, candidate preparation/evaluation, consumer migration

- `Lirico/Component/LyricsSelector.swift`
  - touched by `SR-03`, `SR-05`, `SR-08`
  - risk: changing role from source-priority/quality selector into a reduced or obsolete adapter

- `Lirico/Search/SearchLyricsViewModel.swift`
  - touched by `SR-06`, `SR-07`
  - risk: manual-search state overhaul and automatic-search cancellation/override semantics collide here

### Medium-risk cleanup files

- `Lirico/Preferences/GeneralPreferencesView.swift`
  - touched by `SR-05`, `SR-08`
  - risk: strict-search toggle removal and late cleanup conflict

- `Lirico/Utility/UserDefaultsKeys.swift`
  - touched by `SR-05`, `SR-08`
  - risk: dead defaults removal before final cleanup is complete

### Cross-repo test zones

- `LyricsKit/Tests/LyricsKitTests/Providers/`
  - touched by `SR-01`, `SR-02`, `SR-08`
  - risk: provider-event and LRCLIB test expansion colliding with later hardening

- `LiricoPackage/Tests/LiricoFoundationTests/`
  - touched by `SR-04`, `SR-08`
  - risk: early core tests vs. final full matrix expansion

## 5. Parallelizable story groups

### Safely parallelizable

#### Group A: `SR-02` and `SR-03` after `SR-01`

Why safe enough:
- `SR-02` is LyricsKit LRCLIB-specific.
- `SR-03` is Lirico-side dependency/provider-construction work.
- No direct file overlap across repos from the declared touchpoints.

Recommended note:
- merge `SR-01` first, then branch `SR-02` and `SR-03` separately.

### Conditionally parallelizable

#### Group B: `SR-06` and `SR-07` after `SR-05`

Logical independence:
- `SR-06` is the manual-search branch.
- `SR-07` is the automatic-search branch.

Why they are **not** safely parallel by default:
- both touch `Lirico/Search/SearchLyricsViewModel.swift`
- both touch `Lirico/Component/SearchSettings.swift`
- both consume the newly changed `Lirico/Component/LyricsSearchPipeline.swift`
- `SR-07` crosses into manual apply/select cancellation semantics, which couples it back to the manual surface

Practical recommendation:
- treat them as separate workstreams, but not as independent no-coordination branches
- either:
  1. merge `SR-06` first, then rebase `SR-07`, or
  2. carve any shared ViewModel/manual-override seam into a tiny prep patch before splitting

## 6. Stories that must NOT run in parallel

### `SR-01` and `SR-02`

Reason:
- explicit dependency
- `SR-02` relies on the request album contract introduced in `SR-01`

### `SR-01` and `SR-03`

Reason:
- explicit dependency
- `SR-03` needs the new LyricsKit contract surface and canonical source model

### `SR-03` and `SR-04`

Reason:
- explicit dependency
- `SR-04` is meant to build against the integrated Lirico/LyricsKit substrate from `SR-03`

### `SR-03` and `SR-05`

Reason:
- explicit dependency
- shared hot files: `LyricsSearchPipeline.swift`, `LyricsSelector.swift`, `SearchSettings.swift`

### `SR-04` and `SR-05`

Reason:
- explicit dependency
- `SR-05` consumes the evaluator/ranker types added in `SR-04`

### `SR-05` and `SR-06`

Reason:
- explicit dependency
- `SR-06` needs the evaluated event stream and ranking configuration

### `SR-05` and `SR-07`

Reason:
- explicit dependency
- `SR-07` needs the evaluated event stream and ranking configuration

### `SR-06` and `SR-07` (conservative rule)

Reason:
- heavy overlap in `SearchLyricsViewModel.swift`
- shared overlap in `SearchSettings.swift` and `LyricsSearchPipeline.swift`
- behavior overlap around manual apply/select cancelling automatic work

This is the biggest correction to the earlier high-level phase split: they are parallel in architecture, but not safely parallel in branch execution without coordination.

### `SR-05` and `SR-08`

Reason:
- `SR-08` cleans up strict-search/defaults/test surfaces that `SR-05` is still actively reshaping
- running them together invites churn and premature cleanup

## 7. Recommended implementation waves

### Wave 1 — Shared LyricsKit contract base

Stories:
- `SR-01`

Merge strategy:
- merge directly to trunk/main before any dependent story branches start
- this is the base for all later cross-repo and app-level work

### Wave 2 — Parallel substrate split

Stories:
- `SR-02`
- `SR-03`

Can start together:
- yes, after `SR-01` lands

Merge strategy:
- keep them in separate branches
- merge whichever finishes first
- if `SR-03` lands first, rebase `SR-02` only if LyricsKit test fixtures moved; otherwise no coordination needed

### Wave 3 — Pure core ranking model

Stories:
- `SR-04`

Merge strategy:
- start only after `SR-03` lands
- keep package-only where possible to minimize app-target churn

### Wave 4 — Shared pipeline migration

Stories:
- `SR-05`

Merge strategy:
- make this a clean integration branch
- avoid concurrent cleanup work in `GeneralPreferencesView.swift`, `UserDefaultsKeys.swift`, `SearchSettings.swift`, or `LyricsSelector.swift`
- merge before any consumer-branch rollout begins

### Wave 5 — Consumer rollout

Stories:
- `SR-06`
- `SR-07`

Recommended execution:
- start design/analysis for both after `SR-05`
- implement with **sequenced merges**, not blind parallel branches

Recommended merge order:
1. `SR-06`
2. `SR-07`

Why this order:
- `SR-06` is the larger UI/state refactor and establishes the final manual search surface.
- `SR-07` can then rebase onto that surface and add the smaller manual-override touchpoints it needs.
- This reduces the risk of both stories diverging in `SearchLyricsViewModel.swift`.

Alternative if parallelism is required:
- first land a tiny agreed seam for manual-override/cancellation ownership,
- then split `SR-06` and `SR-07` across separate branches against that seam.

### Wave 6 — Hardening and cleanup

Stories:
- `SR-08`

Merge strategy:
- only start after `SR-02`, `SR-06`, and `SR-07` are merged
- use this wave to remove dead transitional code, expand tests, and tune thresholds
- do not let this wave introduce new product behavior

## Summary recommendation

Best practical rollout:

```text
Wave 1: SR-01
Wave 2: SR-02 || SR-03
Wave 3: SR-04
Wave 4: SR-05
Wave 5: SR-06 -> SR-07
Wave 6: SR-08
```

If you want more concurrency than that, the only place worth forcing it is `SR-06`/`SR-07`, and only after carving out a shared seam first.