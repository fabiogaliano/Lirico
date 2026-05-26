# lyrics-diag

Diagnostic that shows **which lyrics candidates the app finds, how they rank, which one gets auto-picked, and how their timing/metadata differ** — for whatever is playing in the music player Lirico/LyricsX is configured to use.

It reuses the app's real ranking brain (`LyricsXFoundation`: `LyricsCandidateEvaluator` + `LyricsCandidateRanker`) and the same pinned `LyricsKit 1.9.0` providers, so results match the shipping app. It also reads your **real app settings** (`com.fabiogaliano.LyricsX`): source-priority order/toggle, Musixmatch token, and the line filter.

## Usage

```bash
# Auto: pull current track from the configured player + real settings
./diag.sh

# Show more divergent lines / context
./diag.sh --show-lines 20

# Compare RAW provider lines (skip the app's line filter)
./diag.sh --no-prepare

# Override the track manually (skips the player query)
./diag.sh --title "White Flag" --artist "Vince Staples" --album "White Flag" --duration 154.48

# Machine-readable output (for AI/automation — parse instead of scraping the table)
./diag.sh --json
```

First run builds the tool (`swift build`); later runs are instant.

The `--json` form emits a single object: `automatic` / `manual` runs (each with `candidates[]` carrying `rank`, `picked`, `scores`, `lengthSec`, `durationDeltaSec`, `tier`, `visibility`, `enabledLines`/`totalLines`, …), plus `timingGroups[]` with per-group `verdict` (`same-file` / `same-timing` / `drift` / `different-content`), `medianDeltaSec`, `maxLocalDevSec`, and `divergentLines` / `relocatedLines`. Human text is suppressed in this mode.

## What it reports

1. **AUTOMATIC search** (limit 5, album passed) — full ranked candidate table, the `➤` auto-pick, and *why* it beat #2.
2. **MANUAL search** (limit 8, no album → album score neutral for all) — the larger candidate set the search panel would show.
3. **Manual-only results** — what the bigger manual search surfaces that automatic didn't.
4. **Timing divergence** — candidates grouped by identical timing; for each distinct timing, a content-aware (nearest-in-time) line alignment vs the auto-pick: median offset, how many shared lines align within 0.30s, line-by-line drift, relocated (repeated-phrase) lines, and structural extra/missing-line counts.

## Reading the candidate table

```
#  P Source  Title  Artist  Album  Len   dΔ  Sync  Tier  Vis  T A D Al Ovr  en/tot  Reject
```

| Column | Meaning |
|---|---|
| `#` | Rank within that search (ranker order) |
| `P` | `➤` marks the candidate the **automatic** search would auto-pick |
| `Len` | The candidate's `[length]` LRC tag (mm:ss) — *not* its last-line time |
| `dΔ` | Candidate length minus the track duration, in seconds (drives the duration tiebreaker) |
| `Sync` | `line` = line-synced, `karaok` = word-level timetags (≥2 lines & ≥50% coverage) |
| `Tier` | Correctness tier — the **dominant** sort key (`exactT+A` > `strongT+A` > `titleOnly` > `looseT+A` > catalog > `REJECTED`) |
| `Vis` | `normal` shown; `loose` shown only if no normal exists; `unlikely`/`rejected` hidden |
| `T A D Al` | 0–100 sub-scores: Title, Artist, Duration, Album |
| `Ovr` | Composite 0–100 (correctness + tiebreakers) |
| `en/tot` | Enabled vs total lines (filter disables lines; gap = lines the filter removed) |
| `Reject` | Why a candidate was rejected/downgraded |

**The pick order is tiered, not "highest score wins":** tier first, then karaoke-within-window, then overall, then duration, then album, then source priority (only if enabled & scores near-equal), then arrival order. Duration/album are *tiebreakers* — they never promote a wrong-title or wrong-artist candidate.

## Using it for analysis / debugging

Run `./diag.sh` with the suspect song playing, then:

- **"The app picked the wrong lyrics."** Look at the `➤` row vs the one you wanted in the AUTOMATIC table. Compare their `Tier` first (a higher tier always wins). If same tier, compare `Ovr`, then `dΔ` (duration tag), then `Al`. The `beat #2 by:` line names the exact deciding factor. Common cause: the wanted version has a missing/wrong `[length]` tag (`dΔ` huge → `D=0`) or a mismatched album (`Al=20`).

- **"Lyrics are out of sync."** Check the TIMING section. `median Δ` is the constant offset of the picked file vs the alternatives; a large median with everything else aligned = a global lead-in/offset problem (fixable via the `[offset]` tag). Line-by-line drift (the divergence table populates) = a genuinely mis-timed transcription — pick a different candidate.

- **"A version I want is missing."** It may be in the MANUAL table (limit 8 vs 5) or the "manual-only" list. If it's in the `Dropped` block, the `Reject` column says why (`titleMismatch` / `artistMismatch` / `noContent`). `unlikely` rows are hidden behind the app's "Show unlikely results" toggle.

- **"Is the filter eating real lyric lines?"** Compare `./diag.sh` against `./diag.sh --no-prepare`. Watch the `en/tot` column: with the filter on, `en` < `tot` means lines were disabled. If a real lyric line disappears, a filter key is too aggressive (see `LyricsFilterKeys`).

- **"Why did automatic and manual disagree?"** Automatic passes the album (so `Al` is a real tiebreaker and the correct-album copy wins); manual omits it (`Al=50` for all), so manual ranks the same correct-song copies differently. The header prints the active settings (`sourcePriority`, `musixmatch`, `filter`) so you can confirm what was in effect.

- **Reproduce a specific case** without playback: `./diag.sh --title … --artist … --album … --duration <seconds>`. Omit `--album`/`--duration` to see how the pick degrades when that metadata is unavailable (e.g. a player that doesn't report duration → every `D=50`, ties fall to arrival order).

### Tips
- Increase detail with `--show-lines N` (controls how many divergent/relocated lines are listed).
- The tool needs network (it hits NetEase/QQMusic/Kugou/LRCLIB live). Provider failures appear as `✗ … FAILED` in the activity log rather than aborting the run.
- It reads, never writes: no app state, lyrics files, or settings are modified.

## Shared with the app (no drift)

To avoid re-implementing app logic that could silently diverge, the two pieces most likely to change live in the `LyricsXFoundation` package and are used by **both** the app and this tool:

- **`makeProviderDescriptors(musixmatchToken:)`** — the canonical lyrics-source list/order (app's `LyricsSearchPipeline`/`LyricsSelector` and this tool call it).
- **`makeLyricsFilterPredicate(keys:enabled:)`** — the line-filter predicate (app's `LyricsFilter` and this tool call it).

Add or change a provider, or the filter logic, in one place and both follow.

## Faithfulness notes

- `recognizeLanguage()` (app-target only; sets `metadata.language`) is omitted — no effect on ranking/timing.
- Ranker window constants use the app's SR-04 defaults (karaoke 10, loose floor 80) since they aren't user-exposed.
- The line filter *disables* lines (affects `enabled` count + karaoke detection), it doesn't delete them — hence the `en/tot` column.
- Remaining mirrors are intentional (small, tangled with app-only types): the ranking-config mapping (`SearchSettings`, read here from env) and the request shapes (auto: limit 5 + album; manual: limit 8, no album).
