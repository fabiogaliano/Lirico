import Foundation
import LyricsXFoundation

// MARK: - Argument & environment parsing
//
// Track metadata comes in as args (usually supplied by diag.sh from the
// configured player). Real app settings come in as env vars so the wrapper can
// pass them verbatim without shell-quoting an array.

func arg(_ name: String) -> String? {
    let flag = "--\(name)"
    guard let idx = CommandLine.arguments.firstIndex(of: flag),
          idx + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[idx + 1]
}
func hasFlag(_ name: String) -> Bool { CommandLine.arguments.contains("--\(name)") }
func env(_ name: String) -> String? {
    let v = ProcessInfo.processInfo.environment[name]
    return (v?.isEmpty == true) ? nil : v
}

let title = arg("title") ?? ""
let artist = arg("artist") ?? ""
let album = arg("album").flatMap { $0.isEmpty ? nil : $0 }
let duration = arg("duration").flatMap(TimeInterval.init)
let showLines = arg("show-lines").flatMap(Int.init) ?? 12
let playerName = arg("player") ?? "(manual args)"
let jsonMode = hasFlag("json")

// Real app settings (with the app's registered-default fallbacks baked in, so
// the tool is still faithful when run without the wrapper).
let sourcePriorityEnabled = (env("DIAG_SOURCE_PRIORITY_ENABLED") ?? "0") == "1"
let sourcePriorityOrder = (env("DIAG_SOURCE_PRIORITY_ORDER").map { $0.split(separator: ",").map(String.init) }) ?? []
let musixmatchToken = env("DIAG_MUSIXMATCH_TOKEN")
let filterEnabled = (env("DIAG_FILTER_ENABLED") ?? "1") == "1" && !hasFlag("no-prepare")
// Fallback only — diag.sh sources the live list from the app's UserDefaults.plist.
let defaultFilterKeys = ["/(by|title|song|album|artist|singer|lyrics)\\s*[:：∶]", "/\\w+(\\.\\w+){2}", "/^\\s*//\\s*$", "/\\d{8}", "/^\\.$", "作詞", "作词", "作曲", "編曲", "编曲", "収録", "收录", "演唱", "歌手", "歌曲", "制作", "製作", "歌词", "歌詞", "翻譯", "翻译", "插曲", "插入歌", "主题歌", "主題歌", "片頭曲", "片头曲", "片尾曲", "SoundTrack", "アニメ"]
let filterKeys: [String] = {
    guard let json = env("DIAG_FILTER_KEYS_JSON"),
          let data = json.data(using: .utf8),
          let arr = try? JSONDecoder().decode([String].self, from: data) else {
        return defaultFilterKeys
    }
    return arr
}()

guard !title.isEmpty, !artist.isEmpty else {
    FileHandle.standardError.write(Data("error: --title and --artist required (or run via diag.sh)\n".utf8))
    exit(2)
}

// MARK: - Preparation (uses the app's shared predicate builder + filtrate)

// `makeLyricsFilterPredicate` is the same builder the app's LyricsFilter uses,
// so filtering behavior cannot drift from the app. recognizeLanguage() is an
// app-target extension (only sets metadata.language) and has no ranking/timing
// effect, so it is intentionally omitted.
let filterPredicate = makeLyricsFilterPredicate(keys: filterKeys, enabled: filterEnabled)
func prepare(_ lyrics: Lyrics) { lyrics.filtrate(isIncluded: filterPredicate) }

// MARK: - Formatting helpers

func mmss(_ t: TimeInterval?) -> String {
    guard let t = t else { return "—" }
    let n = Int(t.rounded()); return String(format: "%d:%02d", n / 60, n % 60)
}
func tierLabel(_ t: LyricsCandidateMatchTier) -> String {
    switch t {
    case .exactTitleArtist: return "exactT+A"; case .strongTitleArtist: return "strongT+A"
    case .titleOnly: return "titleOnly"; case .looseTitleArtist: return "looseT+A"
    case .exactArtistCatalog: return "exactArt"; case .looseArtistCatalog: return "looseArt"
    case .rejected: return "REJECTED"
    }
}
func visLabel(_ v: LyricsCandidateVisibility) -> String {
    switch v { case .normal: return "normal"; case .looseFallback: return "loose"; case .unlikely: return "unlikely"; case .rejected: return "rejected" }
}
func rejLabel(_ r: LyricsCandidateRejectionReason?) -> String? {
    switch r { case .none: return nil; case .titleMismatch: return "titleMismatch"; case .artistMismatch: return "artistMismatch"; case .noMeaningfulContent: return "noContent" }
}
func sc(_ d: Double) -> String { String(format: "%.0f", d) }

func enabledLines(_ l: Lyrics) -> [LyricsLine] { l.lines.filter { $0.enabled && !$0.content.isEmpty } }

func normLine(_ s: String) -> String {
    let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en")).lowercased()
    let kept = folded.unicodeScalars.map { Character($0).isLetter || Character($0).isNumber ? String(Character($0)) : " " }.joined()
    return kept.split(separator: " ").joined(separator: " ")
}

// MARK: - Search

let configuration = LyricsCandidateRankingConfiguration(
    sourcePriorityEnabled: sourcePriorityEnabled,
    sourcePriorityOrder: sourcePriorityOrder
)
let evaluator = LyricsCandidateEvaluator()
let ranker = LyricsCandidateRanker()

struct RunResult {
    let collected: [EvaluatedLyricsCandidate]
    let ranked: [EvaluatedLyricsCandidate]
    let log: [String]
    let completed: Bool
}

func runSearch(request: LyricsSearchRequest, mode: LyricsSearchMode,
               requestedDuration: TimeInterval?, requestedAlbum: String?,
               timeout: UInt64) async -> RunResult {
    // Provider list comes from the app's shared `makeProviderDescriptors`.
    let group = LyricsProviders.Group(descriptors: makeProviderDescriptors(musixmatchToken: musixmatchToken))
    final class Box { var collected: [EvaluatedLyricsCandidate] = []; var log: [String] = []; var completed = false }
    let box = Box()

    let consume = Task {
        var arrival = 0
        for await ev in group.events(for: request) {
            switch ev {
            case .providerStarted(let s, _): box.log.append("  ▶ \(s) started")
            case .candidate(let s, let lyrics):
                lyrics.metadata.service = s
                prepare(lyrics)  // filter BEFORE evaluate, exactly like the pipeline
                let e = evaluator.evaluate(lyrics: lyrics, mode: mode, requestedDuration: requestedDuration, requestedAlbum: requestedAlbum)
                box.collected.append(.init(lyrics: lyrics, evaluation: e, arrivalIndex: arrival)); arrival += 1
            case .providerFinished(let s, _, let c): box.log.append("  ✓ \(s) finished — \(c) result(s)")
            case .providerFailed(let s, _, let m, let c): box.log.append("  ✗ \(s) FAILED (\(c) before fail): \(m)")
            case .completed: box.completed = true
            }
        }
    }
    let deadline = Task { try? await Task.sleep(nanoseconds: timeout); consume.cancel() }
    await consume.value
    deadline.cancel()
    let ranked = ranker.rankedCandidates(box.collected, mode: mode, configuration: configuration)
    return RunResult(collected: box.collected, ranked: ranked, log: box.log, completed: box.completed)
}

let autoUserInfo = album.map { [LyricsSearchRequest.UserInfoKey.albumName: $0] } ?? [:]
let autoRequest = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist), duration: duration ?? 0, limit: 5, userInfo: autoUserInfo)
let manualRequest = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist), duration: duration ?? 0, limit: 8)
let mode: LyricsSearchMode = .titleAndArtist(title: title, artist: artist)

let autoRun = await runSearch(request: autoRequest, mode: mode, requestedDuration: duration, requestedAlbum: album, timeout: 25_000_000_000)
let manualRun = await runSearch(request: manualRequest, mode: mode, requestedDuration: duration, requestedAlbum: nil, timeout: 30_000_000_000)
let autoPick = ranker.bestCandidate(from: autoRun.collected, mode: mode, configuration: configuration)
let autoPickID = autoPick?.id

// MARK: - Model (one representation rendered as either text or JSON)

struct ScoreSet: Codable { let title, artist, duration, album, overall: Double }
struct CandidateInfo: Codable {
    let rank: Int?          // 1-based among ranked; nil if dropped
    let picked: Bool
    let source: String
    let title, artist, album: String?
    let lengthTag: String
    let lengthSec: Double?
    let durationDeltaSec: Double?
    let sync: String
    let tier: String
    let visibility: String
    let scores: ScoreSet
    let enabledLines, totalLines: Int
    let rejection: String?
    let arrivalIndex: Int
}

func candidateInfo(_ c: EvaluatedLyricsCandidate, rank: Int?, picked: Bool) -> CandidateInfo {
    let e = c.evaluation, l = c.lyrics
    return CandidateInfo(
        rank: rank, picked: picked,
        source: l.metadata.service ?? "?",
        title: l.idTags[.title], artist: l.idTags[.artist], album: l.idTags[.album],
        lengthTag: mmss(l.length), lengthSec: l.length,
        durationDeltaSec: (duration != nil && l.length != nil) ? (l.length! - duration!) : nil,
        sync: e.syncKind == .karaoke ? "karaoke" : "lineSynced",
        tier: tierLabel(e.matchTier), visibility: visLabel(e.visibility),
        scores: ScoreSet(title: e.titleScore, artist: e.artistScore, duration: e.durationScore, album: e.albumScore, overall: e.overallScore),
        enabledLines: enabledLines(l).count, totalLines: l.lines.count,
        rejection: rejLabel(e.rejectionReason), arrivalIndex: c.arrivalIndex
    )
}

func runInfos(_ r: RunResult) -> [CandidateInfo] {
    var infos = r.ranked.enumerated().map { candidateInfo($0.element, rank: $0.offset + 1, picked: $0.element.id == autoPickID) }
    let rankedIDs = Set(r.ranked.map { $0.id })
    let dropped = r.collected.filter { !rankedIDs.contains($0.id) }.sorted { $0.arrivalIndex < $1.arrivalIndex }
    infos += dropped.map { candidateInfo($0, rank: nil, picked: false) }
    return infos
}
let autoInfos = runInfos(autoRun)
let manualInfos = runInfos(manualRun)

// MARK: - Timing model

// Raw-length signature so near-identical lengths (153.0 vs 153.4) don't collide.
func sig(_ c: EvaluatedLyricsCandidate) -> String {
    let l = c.lyrics
    let len = l.length.map { String(format: "%.2f", $0) } ?? "—"
    return "\(l.metadata.service ?? "?")|\(l.idTags[.title] ?? "")|\(l.idTags[.artist] ?? "")|\(l.idTags[.album] ?? "")|\(len)|\(l.lines.count)"
}
func timingSig(_ c: EvaluatedLyricsCandidate) -> String {
    enabledLines(c.lyrics).map { String(format: "%.1f", $0.position) }.joined(separator: ",")
}

struct TimingMember: Codable { let source: String; let lengthTag: String; let lengthSec: Double?; let album: String? }
struct DeltaLine: Codable { let refPos, candPos, deltaSec, localDevSec: Double; let text: String }
struct TimingGroup: Codable {
    let members: [TimingMember]
    let sharesReferenceTiming: Bool
    let candLineCount: Int?
    let contentOverlap: Int?
    let onlyInCand: Int?
    let onlyInRef: Int?
    let medianDeltaSec: Double?
    let maxLocalDevSec: Double?
    let verdict: String?          // "same" | "drift" | "different-content"
    let divergentLines: [DeltaLine]
    let relocatedLines: [DeltaLine]
}

func member(_ c: EvaluatedLyricsCandidate) -> TimingMember {
    TimingMember(source: c.lyrics.metadata.service ?? "?", lengthTag: mmss(c.lyrics.length), lengthSec: c.lyrics.length, album: c.lyrics.idTags[.album])
}

let reference = autoPick ?? autoRun.ranked.first
let refEnabled = reference.map(\.lyrics).map(enabledLines) ?? []
let refLast = refEnabled.last?.position

// Distinct timings across BOTH runs (normal-visibility + the reference),
// deduped by identity first so a file present in both runs isn't double-counted.
var timingGroups: [TimingGroup] = []
if let ref = reference {
    var byIdentity = [String: EvaluatedLyricsCandidate]()
    for c in autoRun.collected + manualRun.collected where c.evaluation.visibility == .normal || c.id == ref.id {
        byIdentity[sig(c)] = c
    }
    var groups: [String: [EvaluatedLyricsCandidate]] = [:]
    for c in byIdentity.values { groups[timingSig(c), default: []].append(c) }
    let refSig = timingSig(ref)

    // The reference's own timing group first (identical-file copies).
    if let same = groups[refSig] {
        timingGroups.append(TimingGroup(
            members: same.map(member), sharesReferenceTiming: true,
            candLineCount: nil, contentOverlap: nil, onlyInCand: nil, onlyInRef: nil,
            medianDeltaSec: nil, maxLocalDevSec: nil, verdict: "same-file", divergentLines: [], relocatedLines: []
        ))
    }

    let others = groups.filter { $0.key != refSig }.values.sorted { ($0.first?.arrivalIndex ?? 0) < ($1.first?.arrivalIndex ?? 0) }
    for members in others {
        guard let cand = members.first else { continue }
        let candEnabled = enabledLines(cand.lyrics)
        var refByText: [String: [Int]] = [:]
        for (i, line) in refEnabled.enumerated() { refByText[normLine(line.content), default: []].append(i) }
        var used = Set<Int>()
        var deltas: [(refPos: TimeInterval, candPos: TimeInterval, text: String)] = []
        var unmatched = 0
        for line in candEnabled {
            // Nearest-in-time match so a repeated phrase (chorus) pairs with the
            // occurrence near its own timestamp, not an arbitrary far repeat.
            let avail = (refByText[normLine(line.content)] ?? []).filter { !used.contains($0) }
            if let idx = avail.min(by: { abs(refEnabled[$0].position - line.position) < abs(refEnabled[$1].position - line.position) }) {
                used.insert(idx)
                deltas.append((refEnabled[idx].position, line.position, line.content))
            } else { unmatched += 1 }
        }
        if deltas.isEmpty {
            timingGroups.append(TimingGroup(
                members: members.map(member), sharesReferenceTiming: false,
                candLineCount: candEnabled.count, contentOverlap: 0, onlyInCand: unmatched, onlyInRef: refEnabled.count,
                medianDeltaSec: nil, maxLocalDevSec: nil, verdict: "different-content", divergentLines: [], relocatedLines: []
            ))
            continue
        }
        let ds = deltas.map { $0.candPos - $0.refPos }
        let median = ds.sorted()[ds.count / 2]
        let relocateThreshold = 15.0
        let alignedItems = deltas.enumerated().filter { abs(ds[$0.offset] - median) <= relocateThreshold }
        let relocatedItems = deltas.enumerated().filter { abs(ds[$0.offset] - median) > relocateThreshold }
        let maxLocal = alignedItems.map { abs(ds[$0.offset] - median) }.max() ?? 0
        let line = { (d: (refPos: TimeInterval, candPos: TimeInterval, text: String)) in
            DeltaLine(refPos: d.refPos, candPos: d.candPos, deltaSec: d.candPos - d.refPos, localDevSec: abs((d.candPos - d.refPos) - median), text: d.text)
        }
        let divergent = alignedItems.map { line($0.element) }.filter { $0.localDevSec > 0.30 }.sorted { $0.localDevSec > $1.localDevSec }
        timingGroups.append(TimingGroup(
            members: members.map(member), sharesReferenceTiming: false,
            candLineCount: candEnabled.count, contentOverlap: deltas.count, onlyInCand: unmatched, onlyInRef: refEnabled.count - deltas.count,
            medianDeltaSec: median, maxLocalDevSec: maxLocal,
            verdict: maxLocal <= 0.30 ? "same-timing" : "drift",
            divergentLines: Array(divergent.prefix(showLines)),
            relocatedLines: relocatedItems.map { line($0.element) }
        ))
    }
}

// MARK: - JSON output

if jsonMode {
    struct RunJSON: Codable { let limit: Int; let albumPassed: Bool; let completed: Bool; let rawCount: Int; let candidates: [CandidateInfo] }
    struct Report: Codable {
        let player: String
        let title, artist: String
        let album: String?
        let durationSec: Double?
        let settings: [String: String]
        let referenceLastLineSec: Double?
        let automatic: RunJSON
        let manual: RunJSON
        let timingGroups: [TimingGroup]
    }
    let report = Report(
        player: playerName, title: title, artist: artist, album: album, durationSec: duration,
        settings: [
            "sourcePriorityEnabled": "\(sourcePriorityEnabled)",
            "sourcePriorityOrder": sourcePriorityOrder.joined(separator: ","),
            "musixmatch": musixmatchToken != nil ? "on" : "off",
            "filterEnabled": "\(filterEnabled)",
            "filterKeyCount": "\(filterKeys.count)",
        ],
        referenceLastLineSec: refLast,
        automatic: RunJSON(limit: 5, albumPassed: album != nil, completed: autoRun.completed, rawCount: autoRun.collected.count, candidates: autoInfos),
        manual: RunJSON(limit: 8, albumPassed: false, completed: manualRun.completed, rawCount: manualRun.collected.count, candidates: manualInfos),
        timingGroups: timingGroups
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(report), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
    exit(0)
}

// MARK: - Text rendering

// Dynamic-width table: columns size to their content (no truncation).
func renderTable(headers: [String], rightAlign: [Bool], ranked: [[String]], dropped: [[String]], droppedLabel: String) -> [String] {
    let n = headers.count
    var w = headers.map { $0.count }
    for r in ranked + dropped { for i in 0..<n { w[i] = max(w[i], r[i].count) } }
    func cell(_ s: String, _ i: Int) -> String {
        let p = max(0, w[i] - s.count)
        return rightAlign[i] ? String(repeating: " ", count: p) + s : s + String(repeating: " ", count: p)
    }
    func row(_ r: [String]) -> String { (0..<n).map { cell(r[$0], $0) }.joined(separator: " ") }
    var out = [row(headers)]
    out.append(String(repeating: "─", count: out[0].count))
    ranked.forEach { out.append(row($0)) }
    if !dropped.isEmpty {
        out.append(String(repeating: "·", count: out[0].count))
        out.append(droppedLabel)
        dropped.forEach { out.append(row($0)) }
    }
    return out
}

let tableHeaders = ["#", "P", "Source", "Title", "Artist", "Album", "Len", "dΔ", "Sync", "Tier", "Vis", "T", "A", "D", "Al", "Ovr", "en/tot", "Reject"]
let tableRight = [false, false, false, false, false, false, false, true, false, false, false, true, true, true, true, true, false, false]
func cells(_ c: CandidateInfo) -> [String] {
    [
        c.rank.map(String.init) ?? "--", c.picked ? "➤" : "",
        c.source, c.title ?? "—", c.artist ?? "—", c.album ?? "—",
        c.lengthTag, c.durationDeltaSec.map { String(format: "%+.0f", $0) } ?? "—",
        c.sync == "karaoke" ? "karaoke" : "line", c.tier, c.visibility,
        sc(c.scores.title), sc(c.scores.artist), sc(c.scores.duration), sc(c.scores.album), sc(c.scores.overall),
        "\(c.enabledLines)/\(c.totalLines)", c.rejection ?? "",
    ]
}
func printRun(_ infos: [CandidateInfo]) {
    let ranked = infos.filter { $0.rank != nil }.map(cells)
    let dropped = infos.filter { $0.rank == nil }.map(cells)
    renderTable(headers: tableHeaders, rightAlign: tableRight, ranked: ranked, dropped: dropped,
                droppedLabel: " Dropped (rejected / loose suppressed by a normal result):").forEach { print($0) }
}

print("")
print("════════════════════════════════════════════════════════════════════════════════════")
print(" LYRICS CANDIDATE DIAGNOSTIC")
print("════════════════════════════════════════════════════════════════════════════════════")
print(" Player   : \(playerName)")
print(" Query    : \"\(title)\" — \(artist)")
print(" Album    : \(album ?? "—")    Duration: \(duration.map { String(format: "%.2fs (%@)", $0, mmss($0)) } ?? "—")")
print(" Settings : sourcePriority=\(sourcePriorityEnabled ? "ON \(sourcePriorityOrder)" : "OFF (order ignored)")  musixmatch=\(musixmatchToken != nil ? "on" : "off")  filter=\(filterEnabled ? "ON (\(filterKeys.count) keys)" : "OFF")")
print(" Ranker   : karaokeWindow=\(Int(configuration.karaokePreferenceWindow))  looseFloor=\(Int(configuration.automaticLooseFallbackMinimumScore))  LyricsKit=1.9.0 (same as app)")
print(" Note     : recognizeLanguage (app-only, sets metadata.language) omitted — no ranking/timing effect.")

print("")
print("══ AUTOMATIC SEARCH (what runs on track change: limit 5, album passed, auto-picks one) ══")
autoRun.log.forEach { print($0) }
print("  completed=\(autoRun.completed)  raw candidates=\(autoRun.collected.count)")
print("")
printRun(autoInfos)
print("")
if let pick = autoInfos.first(where: { $0.picked }) {
    print(" ➤ AUTO-PICK: [\(pick.source)] \"\(pick.title ?? "—")\" — \(pick.artist ?? "—") (album: \(pick.album ?? "—"))")
    print("   tier=\(pick.tier) vis=\(pick.visibility) sync=\(pick.sync)  T=\(sc(pick.scores.title)) A=\(sc(pick.scores.artist)) D=\(sc(pick.scores.duration)) Al=\(sc(pick.scores.album)) → Ovr=\(String(format: "%.2f", pick.scores.overall))")
    let rankedInfos = autoInfos.filter { $0.rank != nil }
    if rankedInfos.count > 1 {
        let r2 = rankedInfos[1], p = pick
        var why = "earlier arrival"
        if p.tier != r2.tier { why = "higher tier (\(p.tier) > \(r2.tier))" }
        else if abs(p.scores.overall - r2.scores.overall) > 0.001 { why = "higher overall (\(String(format: "%.2f", p.scores.overall)) > \(String(format: "%.2f", r2.scores.overall)))" }
        else if p.scores.duration != r2.scores.duration { why = "closer duration (D \(sc(p.scores.duration)) > \(sc(r2.scores.duration)))" }
        else if p.scores.album != r2.scores.album { why = "better album (Al \(sc(p.scores.album)) > \(sc(r2.scores.album)))" }
        let tieWarn = why == "earlier arrival" ? "  ⚠︎ TRUE TIE on every score — decided by network arrival order, so the pick can FLIP between runs" : ""
        print("   beat #2 [\(r2.source)] by: \(why)\(tieWarn)")
    }
} else {
    print(" ➤ NO AUTO-PICK: all rejected, or only loose-fallbacks below the floor (Ovr ≥ \(Int(configuration.automaticLooseFallbackMinimumScore))).")
}

print("")
print("══ MANUAL SEARCH (search panel: limit 8, NO album → album score neutral 50; you pick) ══")
manualRun.log.forEach { print($0) }
print("  completed=\(manualRun.completed)  raw candidates=\(manualRun.collected.count)")
print("")
printRun(manualInfos.map { CandidateInfo(rank: $0.rank, picked: false, source: $0.source, title: $0.title, artist: $0.artist, album: $0.album, lengthTag: $0.lengthTag, lengthSec: $0.lengthSec, durationDeltaSec: $0.durationDeltaSec, sync: $0.sync, tier: $0.tier, visibility: $0.visibility, scores: $0.scores, enabledLines: $0.enabledLines, totalLines: $0.totalLines, rejection: $0.rejection, arrivalIndex: $0.arrivalIndex) })
print("")
print(" In the manual panel YOU choose a row; #1 above is just the default ranked order.")
print(" (Album column still shown for info, but album score is 50 for all — not a tiebreaker here.)")

// Manual-only results (present in manual, absent from automatic).
let autoSigs = Set(autoRun.collected.map(sig))
let manualOnly = manualRun.collected.filter { !autoSigs.contains(sig($0)) }.sorted { $0.arrivalIndex < $1.arrivalIndex }
print("")
print("──────────────────────────────────────────────────────────────────────────────────────")
print(" RESULTS ONLY MANUAL SURFACED (extra slots from limit 8 vs 5, or album-narrowing diffs):")
if manualOnly.isEmpty {
    print("   (none — automatic saw the same set)")
} else {
    for c in manualOnly {
        let l = c.lyrics
        print("   • [\(l.metadata.service ?? "?")] \"\(l.idTags[.title] ?? "—")\" — \(l.idTags[.artist] ?? "—") | al=\(l.idTags[.album] ?? "—") | len=\(mmss(l.length)) | \(tierLabel(c.evaluation.matchTier))/\(visLabel(c.evaluation.visibility)) Ovr=\(sc(c.evaluation.overallScore))")
    }
}

// MARK: - Timing section

print("")
print("══════════════════════════════════════════════════════════════════════════════════════")
print(" TIMING DIVERGENCE ANALYSIS")
print("══════════════════════════════════════════════════════════════════════════════════════")
guard let ref = reference else {
    print(" No reference candidate to compare.")
    print("")
    exit(0)
}
print(" Reference (auto-pick): [\(ref.lyrics.metadata.service ?? "?")] al=\(ref.lyrics.idTags[.album] ?? "—") len-tag=\(mmss(ref.lyrics.length)) offset=\(ref.lyrics.offset)ms")
print("   \(refEnabled.count) enabled lines · first @ \(mmss(refEnabled.first?.position)) · LAST LINE @ \(mmss(refLast)) (\(String(format: "%.1f", refLast ?? 0))s)"
      + (duration.map { "  vs track \(mmss($0)) (\(String(format: "%.1f", $0))s) → last line is \(String(format: "%.1f", $0 - (refLast ?? 0)))s before track end" } ?? ""))

func describe(_ members: [TimingMember]) -> String {
    members.map { "[\($0.source)] len=\($0.lengthTag) al=\($0.album ?? "—")" }.joined(separator: ", ")
}
for g in timingGroups {
    if g.sharesReferenceTiming {
        let others = g.members.filter { !($0.source == (ref.lyrics.metadata.service ?? "?") && $0.lengthSec == ref.lyrics.length && $0.album == ref.lyrics.idTags[.album]) }
        if !others.isEmpty {
            print("")
            print(" \(others.count) other candidate(s) carry the auto-pick's EXACT timing (identical file, metadata aside):")
            print("   " + describe(others))
        }
        continue
    }
    print("────────────────────────────────────────────────────────────────────────────────────")
    print(" vs \(describe(g.members))" + (g.members.count > 1 ? "  (\(g.members.count) candidates share this timing)" : ""))
    if g.verdict == "different-content" {
        print("   content overlap: 0/\(g.candLineCount ?? 0) — ⚠︎ entirely different transcription.")
        continue
    }
    print("   content overlap: \(g.contentOverlap ?? 0)/\(g.candLineCount ?? 0) cand lines match ref text  (\(g.onlyInCand ?? 0) only-in-cand, \(g.onlyInRef ?? 0) only-in-ref)")
    print(String(format: "   timing: median Δ=%+.2fs  (max local dev %.2fs)", g.medianDeltaSec ?? 0, g.maxLocalDevSec ?? 0))
    if g.verdict == "same-timing" {
        print(String(format: "   VERDICT: SAME timing — shared lines match within 0.30s, shifted whole by ~%+.2fs (global offset).", g.medianDeltaSec ?? 0))
    } else {
        print(String(format: "   VERDICT: line-by-line timing drift up to %.2fs (beyond the %+.2fs constant). Most divergent aligned lines:", g.maxLocalDevSec ?? 0, g.medianDeltaSec ?? 0))
        print("     " + "ref→cand".padding(toLength: 16, withPad: " ", startingAt: 0) + "  Δ          vs offset   line")
        for d in g.divergentLines {
            print("     " + String(format: "%.1f→%.1f", d.refPos, d.candPos).padding(toLength: 16, withPad: " ", startingAt: 0)
                  + "  " + String(format: "%+.2fs", d.deltaSec).padding(toLength: 9, withPad: " ", startingAt: 0)
                  + "  " + String(format: "%.2fs", d.localDevSec).padding(toLength: 10, withPad: " ", startingAt: 0)
                  + "  " + String(d.text.prefix(40)))
        }
    }
    if !g.relocatedLines.isEmpty {
        print("   \(g.relocatedLines.count) relocated line(s) (same words, very different position — structural, not drift):")
        for d in g.relocatedLines.prefix(5) {
            print("     " + String(format: "%.1f→%.1f", d.refPos, d.candPos).padding(toLength: 16, withPad: " ", startingAt: 0)
                  + "  " + String(format: "%+.1fs", d.deltaSec).padding(toLength: 9, withPad: " ", startingAt: 0)
                  + "              " + String(d.text.prefix(40)))
        }
    }
}

print("")
print(" Reading it: SAME timing + a constant median Δ = one synced file reused under different")
print(" metadata (the usual case). Line-by-line divergence = a genuinely different transcription")
print(" or edit. The 'only-in-cand / only-in-ref' counts show structural differences (extra/missing lines).")
print("══════════════════════════════════════════════════════════════════════════════════════")
