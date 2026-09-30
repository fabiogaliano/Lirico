import Testing
@testable import LiricoFoundation

@Suite("Source order normalization")
struct SourceOrderNormalizationTests {
    @Test func emptySavedOrderUsesKnownOrder() {
        #expect(normalizedSourceOrder([], known: ["A", "B"]) == ["A", "B"])
    }

    @Test func keepsSavedOrderOfKnownSources() {
        #expect(normalizedSourceOrder(["B", "A"], known: ["A", "B"]) == ["B", "A"])
    }

    @Test func dropsRemovedSourcesAndAppendsNewOnes() {
        #expect(normalizedSourceOrder(["C", "B", "Gone"], known: ["A", "B", "C"]) == ["C", "B", "A"])
    }
}
