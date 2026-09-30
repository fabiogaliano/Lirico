import Foundation
import Testing
@testable import LiricoFoundation

// MARK: - Helpers

private let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
private let configuration = LyricsCandidateRankingConfiguration()

private func lineSynced(title: String = "lacy", artist: String = "Olivia Rodrigo") -> Lyrics {
    Lyrics("[ti:\(title)]\n[ar:\(artist)]\n[00:01.000]line one\n[00:05.000]line two")!
}

private func karaoke(title: String = "lacy", artist: String = "Olivia Rodrigo") -> Lyrics {
    var lrc = "[ti:\(title)]\n[ar:\(artist)]\n"
    for i in 0 ..< 4 {
        let ts = String(format: "[00:%02d.000]", i * 5)
        lrc += "\(ts)lyric line \(i + 1)\n\(ts)[tt]<0,0><500,4>\n"
    }
    return Lyrics(lrc)!
}

private func evaluate(_ lyrics: Lyrics) -> LyricsCandidateEvaluation {
    LyricsCandidateEvaluator().evaluate(lyrics: lyrics, mode: mode, requestedDuration: nil, requestedAlbum: nil)
}

private func candidate(_ lyrics: Lyrics, arrival: Int = 0) -> EvaluatedLyricsCandidate {
    EvaluatedLyricsCandidate(lyrics: lyrics, evaluation: evaluate(lyrics), arrivalIndex: arrival)
}

private func selection(_ policy: AutomaticAcceptancePolicy = .normal) -> AutomaticLyricsSelection {
    AutomaticLyricsSelection(mode: mode, policy: policy, configuration: configuration)
}

private func interims(_ decisions: [AutomaticLyricsSelection.Decision]) -> [Lyrics] {
    decisions.compactMap { if case .interim(let lyrics) = $0 { lyrics } else { nil } }
}

private func supporting(_ decisions: [AutomaticLyricsSelection.Decision]) -> [[Lyrics]] {
    decisions.compactMap { if case .supporting(let lyrics) = $0 { lyrics } else { nil } }
}

private func finished(_ decision: AutomaticLyricsSelection.Decision) -> (accepted: Lyrics?, supporting: [Lyrics]) {
    guard case .finished(let accepted, let supporting) = decision else {
        Issue.record("expected .finished")
        return (nil, [])
    }
    return (accepted, supporting)
}

// MARK: - Selection

@Suite("Automatic lyrics selection")
struct AutomaticLyricsSelectionTests {
    @Test func firstAcceptableCandidateIsShownAsInterim() {
        var selection = selection()
        let exact = lineSynced()
        let decisions = selection.add(candidate(exact), displayed: nil)
        #expect(interims(decisions).map(ObjectIdentifier.init) == [ObjectIdentifier(exact)])
        #expect(supporting(decisions).count == 1)
    }

    @Test func noInterimWhenBestIsAlreadyDisplayed() {
        var selection = selection()
        let exact = lineSynced()
        let decisions = selection.add(candidate(exact), displayed: exact)
        #expect(interims(decisions).isEmpty)
    }

    @Test func laterKaraokeReplacesLineSyncedAndKeepsItAsSupporting() {
        var selection = selection()
        let first = lineSynced()
        _ = selection.add(candidate(first, arrival: 0), displayed: nil)
        let better = karaoke()
        let decisions = selection.add(candidate(better, arrival: 1), displayed: first)
        #expect(interims(decisions).first === better)
        #expect(supporting(decisions).last?.contains { $0 === first } == true)
        #expect(finished(selection.finish(displayed: better)).accepted === better)
    }

    @Test func wrongSongIsNeverSupportingEvidence() {
        var selection = selection()
        let exact = lineSynced()
        let other = lineSynced(title: "vampire")
        _ = selection.add(candidate(exact, arrival: 0), displayed: nil)
        _ = selection.add(candidate(other, arrival: 1), displayed: exact)
        #expect(!finished(selection.finish(displayed: exact)).supporting.contains { $0 === other })
    }

    @Test func nothingCollectedFinishesWithNothing() {
        let result = finished(selection().finish(displayed: nil))
        #expect(result.accepted == nil)
        #expect(result.supporting.isEmpty)
    }

    @Test func localLineSyncedIsNotReplacedByAnEquallyGoodOne() {
        let local = lineSynced()
        var selection = selection(.localUpgradeOnly(local: evaluate(local)))
        let remote = lineSynced()
        #expect(selection.add(candidate(remote), displayed: local).isEmpty)
        let result = finished(selection.finish(displayed: local))
        #expect(result.accepted == nil)
        #expect(result.supporting.contains { $0 === remote })
        #expect(!result.supporting.contains { $0 === local })
    }

    @Test func localLineSyncedIsUpgradedToKaraoke() {
        let local = lineSynced()
        var selection = selection(.localUpgradeOnly(local: evaluate(local)))
        let remote = karaoke()
        #expect(interims(selection.add(candidate(remote), displayed: local)).first === remote)
        #expect(finished(selection.finish(displayed: local)).accepted === remote)
    }
}

// MARK: - Supporting lyrics

@Suite("Supporting lyrics")
struct SupportingLyricsTests {
    @Test func dropsSelectedAndRepeatsKeepingOrder() {
        let a = lineSynced(), b = lineSynced(), c = lineSynced()
        let result = SupportingLyrics.bounded([a, b, a, c], excluding: b)
        #expect(result.map(ObjectIdentifier.init) == [a, c].map(ObjectIdentifier.init))
    }

    @Test func capsAtLimit() {
        let many = (0 ..< SupportingLyrics.limit + 5).map { _ in lineSynced() }
        #expect(SupportingLyrics.bounded(many, excluding: nil).count == SupportingLyrics.limit)
    }
}

// MARK: - Query

@Suite("Lyrics search query")
struct LyricsSearchQueryTests {
    @Test func automaticSendsAlbumOnlyWhenPresent() {
        let withAlbum = LyricsSearchQuery.automatic(title: "lacy", artist: "Olivia Rodrigo", album: "GUTS", duration: 177)
        #expect(withAlbum.request.userInfo[LyricsSearchRequest.UserInfoKey.albumName] == "GUTS")
        #expect(withAlbum.request.searchTerm == .info(title: "lacy", artist: "Olivia Rodrigo"))
        let noAlbum = LyricsSearchQuery.automatic(title: "lacy", artist: "Olivia Rodrigo", album: "", duration: nil)
        #expect(noAlbum.request.userInfo.isEmpty)
        #expect(noAlbum.request.duration == 0)
    }

    @Test func manualSearchesByWhicheverFieldIsFilled() {
        let titleOnly = LyricsSearchQuery.manual(title: " lacy ", artist: "  ", duration: nil)
        #expect(titleOnly?.mode == .titleOnly(title: "lacy"))
        #expect(titleOnly?.request.searchTerm == .keyword("lacy"))
        let both = LyricsSearchQuery.manual(title: "lacy", artist: "Olivia Rodrigo", duration: 177)
        #expect(both?.mode == mode)
        #expect(both?.requestedAlbum == nil)
        #expect(LyricsSearchQuery.manual(title: " ", artist: "", duration: nil) == nil)
    }
}
