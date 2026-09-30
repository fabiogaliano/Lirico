import Foundation
import Testing
@testable import LiricoFoundation

private func lyrics(karaoke: Bool) -> Lyrics {
    var lrc = "[ti:lacy]\n[ar:Olivia Rodrigo]\n"
    for i in 0 ..< 4 {
        let ts = String(format: "[00:%02d.000]", i * 5)
        lrc += "\(ts)lyric line \(i + 1)\n"
        if karaoke { lrc += "\(ts)[tt]<0,0><500,4>\n" }
    }
    return Lyrics(lrc)!
}

private func plan(_ find: LocalLyricsFind?) -> LocalSearchPlan {
    LocalSearchPlan(after: find, title: "lacy", artist: "Olivia Rodrigo", duration: nil, album: nil)
}

@Suite("Local search plan")
struct LocalSearchPlanTests {
    @Test func localKaraokeSkipsTheRemoteSearch() {
        #expect(!plan(.complete(lyrics(karaoke: true))).needsRemoteSearch)
    }

    @Test func localLineSyncedOnlyGivesWayToAnUpgrade() {
        let result = plan(.complete(lyrics(karaoke: false)))
        #expect(result.needsRemoteSearch)
        guard case .localUpgradeOnly = result.policy else {
            Issue.record("expected .localUpgradeOnly")
            return
        }
    }

    @Test func savedLRCOrNothingSearchesNormally() {
        for find in [LocalLyricsFind.savedLRC(lyrics(karaoke: true)), nil] {
            let result = plan(find)
            #expect(result.needsRemoteSearch)
            guard case .normal = result.policy else {
                Issue.record("expected .normal")
                return
            }
        }
    }
}
