import Testing
@testable import LiricoFoundation

/// Source names are spelled out rather than read from `ServiceID.displayName`: they are the
/// keys of the user's saved source-priority order, so a rename must fail here.
@Suite("Provider descriptors")
struct LyricsProviderDescriptorsTests {
    @Test("Without a Musixmatch token only the token-free sources are queried", arguments: [nil, ""] as [String?])
    func withoutToken(token: String?) {
        #expect(makeProviderDescriptors(musixmatchToken: token).map(\.source) == ["NetEase", "QQMusic", "Kugou", "LRCLIB"])
    }

    @Test func aMusixmatchTokenAddsMusixmatchLast() {
        #expect(
            makeProviderDescriptors(musixmatchToken: "token").map(\.source)
                == ["NetEase", "QQMusic", "Kugou", "LRCLIB", "Musixmatch"]
        )
    }
}
