import Foundation
import Testing
@testable import LiricoFoundation

private func tags(_ pairs: [(index: Int, time: TimeInterval)]) -> [KaraokeTiming.Tag] {
    pairs.map { KaraokeTiming.Tag(index: $0.index, time: $0.time) }
}

@Suite("Karaoke timing")
struct KaraokeTimingTests {
    private let line = tags([(0, 0.5), (4, 1.5), (10, 2.5)])

    @Test func noTagsFillsNothing() {
        #expect(KaraokeTiming.sungCharacters(elapsed: 1, tags: []) == 0)
    }

    @Test func clampsBeforeFirstAndAfterLastTag() {
        #expect(KaraokeTiming.sungCharacters(elapsed: 0, tags: line) == 0)
        #expect(KaraokeTiming.sungCharacters(elapsed: 9, tags: line) == 10)
    }

    @Test func interpolatesBetweenTags() {
        #expect(KaraokeTiming.sungCharacters(elapsed: 1.0, tags: line) == 2)
        #expect(KaraokeTiming.sungCharacters(elapsed: 2.0, tags: line) == 7)
    }

    @Test func tagsSharingATimeSkipToTheLaterOne() {
        let stacked = tags([(0, 0), (3, 1), (6, 1), (9, 2)])
        #expect(KaraokeTiming.sungCharacters(elapsed: 1.5, tags: stacked) == 8)
        #expect(KaraokeTiming.sungCharacters(elapsed: 0.99, tags: stacked) == 3)
    }

    @Test func wordStartIsLastTagAtOrBeforeCharacter() {
        #expect(KaraokeTiming.wordStart(atCharacter: 4, tags: line) == 1.5)
        #expect(KaraokeTiming.wordStart(atCharacter: 7, tags: line) == 1.5)
        #expect(KaraokeTiming.wordStart(atCharacter: 30, tags: line) == 2.5)
    }

    @Test func wordStartBeforeEveryTagIsLineStart() {
        #expect(KaraokeTiming.wordStart(atCharacter: 2, tags: tags([(3, 0.4)])) == 0)
    }
}
