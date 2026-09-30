import Foundation
import Testing
@testable import LiricoFoundation

private let mode = LyricsSearchMode.titleAndArtist(title: "lacy", artist: "Olivia Rodrigo")
private let configuration = LyricsCandidateRankingConfiguration()

private func candidate(title: String, artist: String, karaoke: Bool = false, arrival: Int) -> EvaluatedLyricsCandidate {
    var lrc = "[ti:\(title)]\n[ar:\(artist)]\n"
    for i in 0 ..< 4 {
        let ts = String(format: "[00:%02d.000]", i * 5)
        lrc += "\(ts)lyric line \(i + 1)\n"
        if karaoke { lrc += "\(ts)[tt]<0,0><500,4>\n" }
    }
    let lyrics = Lyrics(lrc)!
    let evaluation = LyricsCandidateEvaluator().evaluate(lyrics: lyrics, mode: mode, requestedDuration: nil, requestedAlbum: nil)
    return EvaluatedLyricsCandidate(lyrics: lyrics, evaluation: evaluation, arrivalIndex: arrival)
}

@Suite("Manual search results")
struct ManualSearchResultsTests {
    private let exact = candidate(title: "lacy", artist: "Olivia Rodrigo", arrival: 0)
    private let exactKaraoke = candidate(title: "lacy", artist: "Olivia Rodrigo", karaoke: true, arrival: 1)
    private let wrongArtist = candidate(title: "lacy", artist: "Ed Sheeran", arrival: 2)
    private let otherSong = candidate(title: "drivers license", artist: "Olivia Rodrigo", arrival: 3)

    private var results: ManualSearchResults {
        var results = ManualSearchResults(mode: mode)
        results.append([exact, wrongArtist])
        results.append([otherSong, exactKaraoke])
        return results
    }

    @Test func unlikelyResultsAreOnlyOfferedOnRequestAndAfterTheLikelyOnes() {
        let hidden = results.offered(includeUnlikely: false, configuration: configuration).map(\.lyrics)
        #expect(hidden.map(ObjectIdentifier.init) == [exactKaraoke.lyrics, exact.lyrics].map(ObjectIdentifier.init))
        let shown = results.offered(includeUnlikely: true, configuration: configuration).map(\.lyrics)
        #expect(shown.map(ObjectIdentifier.init) == [exactKaraoke.lyrics, exact.lyrics, wrongArtist.lyrics].map(ObjectIdentifier.init))
        #expect(results.unlikelyCount == 1)
    }

    @Test func aDifferentSongIsNeverOffered() {
        let shown = results.offered(includeUnlikely: true, configuration: configuration)
        #expect(!shown.contains { $0.lyrics === otherSong.lyrics })
    }

    @Test func supportingEvidenceIsTheOtherSameSongResults() {
        let supporting = results.supportingLyrics(excluding: exactKaraoke.lyrics)
        #expect(supporting.map(ObjectIdentifier.init) == [ObjectIdentifier(exact.lyrics)])
    }
}
