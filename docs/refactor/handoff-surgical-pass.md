# Handoff — Surgical Deepening Pass

Single-session pass of small, low-risk refactors that scored well on the
project's stated objectives: elegant codebase, easy to edit by humans AND
AI agents (navigability via grep / file names / signatures), future
bullet-proof. None of these items individually take more than ~30 minutes.

You are continuing architectural work on Lirico at
`/Users/f/Core/dev/projects/Lirico` — a macOS menu-bar lyrics app (Swift 5
Xcode project, Combine-driven, singletons as house style). Read CLAUDE.md in
the repo root before starting; it documents the architecture and the build
command.

## What's already done (don't repeat)

Recent commits on `main`:

```
9b8386d0 fix: gate ChineseConverter in writeToiTunes legacy-LRC branch on lyrics language
aa8f4dc4 refactor: extract SearchBlocklist
e08712d6 refactor: extract LocalLyricsLoader
fa0b70a5 fix: convert Chinese main lines in HUD scroll view to match other displays
1a02a035 refactor: route writeToiTunes per-line export through LineRenderer
9fa101c4 refactor: drop unused NSStatusItem.isVisibe extension
2cb5b55a refactor: inline AutoActivateWindowController pass-through
```

The `Lirico/Component/` directory holds extracted modules:
`LineRenderer`, `LyricsPreparer`, `LyricsSelector`, `PlaybackClock`,
`LocalLyricsLoader`, `SearchBlocklist`. Match their established style:
doc-comment header explaining what the module owns and why, `// MARK:`
sections for grouped functions, `enum ModuleName` for stateless namespaces,
`final class ModuleName` with eager init for stateful singletons.

## Orchestration pattern (proven to work)

For each item below:

1. **Decide if the change warrants an agent.** Items 2 and 3 are mechanical
   enough to do directly. Items 1 and 4 benefit from an implementation
   agent + an independent reviewer.

2. **Implementation agent** (when used): prompt it with specific files +
   line numbers, behavior constraints, where to put the new file, the
   `project.pbxproj` add pattern (4 lines per new file — see the
   PlaybackClock / LocalLyricsLoader pattern), the build command, and an
   explicit "do not commit" instruction.

3. **Read the agent's diff yourself**, then spawn an **independent review
   agent** with explicit checks: build green, deletion-test grep, lint
   scan, scenario trace where applicable.

4. **You commit** (not the agent). Before each commit:
   ```
   git -C /Users/f/Core/dev/projects/Lirico checkout -- "Lirico/Supporting Files/Info.plist"
   ```
   `xcodebuild` bumps `CFBundleVersion` and `LIRICO_BUILD_TIME` as a build-script
   side effect; those belong in separate `chore: bump build number`
   commits, not in refactor commits.

5. Commit subject format: `refactor: <verb> <noun>` or `chore: ...` for
   metadata-only changes. Body: 2-3 sentences explaining why, plus any
   latent fix surfaced as a side effect.

## Verification

```
xcodebuild -project /Users/f/Core/dev/projects/Lirico/Lirico.xcodeproj \
  -scheme Lirico -configuration Debug build 2>&1 | \
  grep -E "(BUILD|error:|warning:)" | tail -10
```

Must end with `** BUILD SUCCEEDED **`. swiftlint is not installed locally;
do manual lint scans against `.swiftlint.yml` (`line_length: 150`).

## Renames are authorized

The project owner has explicitly waived "preserve names for stability" —
rename anything where the new name is more meaningful, EXCEPT classes
referenced by Interface Builder via `customClass=` or `objectClassName=`.
For IB-referenced classes, either:
- Preserve the Obj-C runtime name with `@objc(OldName) class NewSwiftName`
  so IB still resolves the binding (Swift name changes, IB string survives), OR
- Update every IB reference in lockstep (riskier).

## Work plan — four items

### Item 1 — Move AlphaColorWell to its own file

**Why**: `class AlphaColorWell: NSColorWell` is buried at line 58 of
`Lirico/Preferences/PreferenceDisplayViewController.swift`. Hidden classes
inside unrelated VCs are a navigability landmine — file naming is the
primary index for both humans and grep-driven agents.

**Steps**:
1. Read `Lirico/Preferences/PreferenceDisplayViewController.swift` to
   understand AlphaColorWell's class declaration boundaries and any imports
   it relies on.
2. Verify no IB references by grepping `customClass="AlphaColorWell"` and
   `customClass=\"AlphaColorWell\"` in `.storyboard` and `.xib` files. If
   present, the move preserves them (we're moving the file, not renaming).
3. Create `Lirico/Preferences/AlphaColorWell.swift` with the class
   declaration verbatim and the minimal set of imports needed (likely just
   `AppKit`).
4. Delete the class block from `PreferenceDisplayViewController.swift`.
5. Add four entries to `project.pbxproj` using UUIDs
   `E9FA2B0D2E9000000007AA0D` (file ref) and `E9FA2B0E2E9000000007AA0E`
   (build file). Insert sites: after the LocalLyricsLoader entries in the
   PBXBuildFile section, PBXFileReference section, the Preferences group
   (look for the existing PreferenceDisplayViewController.swift reference
   for the group location), and the Sources build phase.

**Optional rename consideration**: the name `AlphaColorWell` is already
descriptive — it's an NSColorWell that supports alpha. No rename.

**Commit**: `refactor: extract AlphaColorWell to its own file`

### Item 2 — Move FilterKey to its own file (optionally rename)

**Why**: Same rationale as Item 1. `FilterKey` is at the bottom of
`Lirico/Preferences/PreferenceFilterViewController.swift` (lines 32-56).

**Critical trap warning**: FilterKey is load-bearing for the NSArrayController
bindings in `Preferences.storyboard` (lines 1202-1209, references
`objectClassName="FilterKey"` and `classReference className="FilterKey"`).
The class's runtime name MUST resolve to "FilterKey" or IB will silently
break.

**Steps**:
1. Read the FilterKey class declaration in
   `PreferenceFilterViewController.swift` lines 32-56.
2. Create `Lirico/Preferences/FilterKey.swift`.
3. **Decision: rename or not.**
   - If keeping the name: move the declaration verbatim, `@objc(FilterKey)`
     line preserved.
   - If renaming to `LyricsFilterKeyword` (more descriptive): use
     `@objc(FilterKey) class LyricsFilterKeyword: NSObject, NSCoding { ... }`
     — Swift name changes, IB binding string survives. Update the call site
     in `PreferenceFilterViewController.swift`:
     `@objc dynamic var directFilter = [FilterKey]()` →
     `@objc dynamic var directFilter = [LyricsFilterKeyword]()`, and the
     `.map { FilterKey(keyword: $0) }` → `.map { LyricsFilterKeyword(keyword: $0) }`.

   **Recommendation**: take the rename. `FilterKey` is cryptic out of
   context; `LyricsFilterKeyword` says exactly what it is.
4. Add four `project.pbxproj` entries with UUIDs
   `E9FA2B0F2E9000000008BB0F` (file ref) and `E9FA2B102E9000000008BB10`
   (build file).

**Commit** (if you renamed): `refactor: extract FilterKey to its own file and rename to LyricsFilterKeyword`
**Commit** (if you kept the name): `refactor: extract FilterKey to its own file`

### Item 3 — Banner CXExtensions as vendored

**Why**: `Lirico/Utility/CXExtensions/` is ~972 lines vendored from the
CombineX project. It currently weights like real Lirico code in any
file-tree scan or grep, but it's third-party utility code. A one-line
banner per file flips the agent's mental model in one glance: "vendored,
don't fix."

**Steps**:
1. List the 8 files in `Lirico/Utility/CXExtensions/`:
   `AnyScheduler.swift`, `Blocking.swift`, `DelayedAutoCancellable.swift`,
   `IgnoreError.swift`, `Invoke.swift`, `SelfRetainedCancellable.swift`,
   `Signal.swift`, `WeakAssign.swift`.
2. For each, add at the top BEFORE the imports:
   ```swift
   // Vendored from CombineX (https://github.com/cx-org/CombineX).
   // Do not modify — keep in sync with upstream.

   ```
3. No code changes. No `project.pbxproj` changes.

**Optional**: if the existing files already have copyright/license headers,
add the vendoring banner above them.

**Do NOT**: extract these into a separate SPM target as the original
proposal suggested. That's a build-system change with risks disproportionate
to the readability win.

**Commit**: `chore: mark CXExtensions as vendored from CombineX`

This is `chore:` not `refactor:` because no code logic changes.

### Item 4 — Extract artwork fetching from SearchLyricsViewController

**Why**: `URLSession.shared.dataTask` is called from
`Lirico/Search/SearchLyricsViewController.swift:245` — a view controller
making network calls is a layer leak. Concentrating network I/O in a named
function makes the seam discoverable.

**Steps**:
1. Grep first: `grep -rn "URLSession" --include="*.swift" /Users/f/Core/dev/projects/Lirico/Lirico/` —
   confirm this is the only site. If there are more, decide whether to
   centralize them all or scope to just this one (default: just this one;
   note any other sites for a future pass).
2. Read `SearchLyricsViewController.swift` around lines 240-270 to
   understand the full call shape: what's the completion expecting? Does
   it dispatch back to main queue? How is failure handled?
3. Create `Lirico/Search/ArtworkFetcher.swift` with a single FREE FUNCTION:
   ```swift
   import AppKit

   /// Fetches an artwork image from a URL. Calls back on the main queue.
   /// Returns nil on any network or decoding failure.
   func fetchArtwork(url: URL, completion: @escaping (NSImage?) -> Void) {
       URLSession.shared.dataTask(with: url) { data, _, _ in
           let image = data.flatMap { NSImage(data: $0) }
           DispatchQueue.main.async {
               completion(image)
           }
       }.resume()
   }
   ```
   **Adjust the signature to match the existing call site exactly** —
   preserve error handling and dispatch semantics byte-identically. The
   pseudocode above is illustrative.
4. Replace the call site in `SearchLyricsViewController.swift` with the
   new function call.
5. Add four `project.pbxproj` entries with UUIDs
   `E9FA2B112E9000000009CC11` (file ref) and `E9FA2B122E9000000009CC12`
   (build file).

**Do NOT**: introduce a `protocol ArtworkFetching` with a fake adapter.
That's testability-bias overdesign for a codebase with no tests and one
production call site. The free function gives you the layer separation
without the ceremony. If the search UI ever grows more network calls,
revisit then.

**Commit**: `refactor: extract artwork fetching from SearchLyricsViewController`

## After each commit, report

One-paragraph summary: what changed, anything surprising, build green
confirmation. After all four commits land, report a final summary table
matching the prior session's wrap-up format:

| Commit | Type | Summary |
|--------|------|---------|

## End-of-session checklist

- [ ] All 4 commits landed on `main`
- [ ] `git -C /Users/f/Core/dev/projects/Lirico status` is clean
- [ ] `git log --oneline -5` shows the 4 new commits + prior `9b8386d0`
- [ ] Build succeeds (`** BUILD SUCCEEDED **`)
- [ ] Deletion-test greps confirm the moves:
  - `grep -rn "class AlphaColorWell" --include="*.swift" /Users/f/Core/dev/projects/Lirico/Lirico/` → only `Preferences/AlphaColorWell.swift`
  - `grep -rn "@objc(FilterKey)" --include="*.swift" /Users/f/Core/dev/projects/Lirico/Lirico/` → only `Preferences/FilterKey.swift`
  - `grep -rn "URLSession.shared.dataTask" --include="*.swift" /Users/f/Core/dev/projects/Lirico/Lirico/` → only `Search/ArtworkFetcher.swift`
- [ ] Do NOT push or open a PR unless explicitly asked.

## Project guardrails (don't violate without asking)

- Swift 5 in the Xcode project setting, Swift 6.2 in `LiricoPackage/Package.swift`.
- LyricsKit and MusicPlayer come from external SPM packages — don't modify them.
- The MusicPlayer package's `playbackTime` and `playbackState.time` are
  LIVE values when playing (anchor + Date.now interpolation), SNAPSHOT
  when paused.
- ChineseConverter and NSPredicate.lyricsPredicate use a lazy
  fileprivate-observer pattern — leave alone.
- No tests exist; do not invent a test suite.
- `project.pbxproj` is UTF-8 text despite git showing diffs as "Bin".
- Don't skip pre-commit hooks (`--no-verify`).
