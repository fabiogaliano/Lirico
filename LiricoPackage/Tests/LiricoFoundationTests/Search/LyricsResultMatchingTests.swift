import Testing
import Foundation
@testable import LiricoFoundation

// MARK: - Helpers

private func makeLyrics(
    lrcBody: String = "[00:01.000]line one\n[00:05.000]line two",
    service: String? = nil,
    serviceToken: String? = nil
) -> Lyrics {
    let lyrics = Lyrics(lrcBody)!
    if let service { lyrics.metadata.service = service }
    if let serviceToken { lyrics.metadata.serviceToken = serviceToken }
    return lyrics
}

// MARK: - Service-key tier

@Test
func matchesWhenSameServiceAndToken() {
    let a = makeLyrics(service: "NetEase", serviceToken: "123")
    let b = makeLyrics(service: "NetEase", serviceToken: "123")
    #expect(a.isSameResult(as: b))
}

@Test
func differsWhenSameServiceDifferentToken() {
    let a = makeLyrics(service: "NetEase", serviceToken: "123")
    let b = makeLyrics(service: "NetEase", serviceToken: "456")
    #expect(!a.isSameResult(as: b))
}

@Test
func differsWhenDifferentServiceEvenWithIdenticalBody() {
    // Two providers can return identical text; they are still distinct results
    // the user could switch between, so the service key wins over the body.
    let body = "[00:01.000]same\n[00:05.000]text"
    let a = makeLyrics(lrcBody: body, service: "NetEase", serviceToken: "1")
    let b = makeLyrics(lrcBody: body, service: "Kugou", serviceToken: "1")
    #expect(!a.isSameResult(as: b))
}

// MARK: - Body-fingerprint fallback

@Test
func matchesDiskLoadedAgainstServiceResultByBody() {
    // A disk-loaded current lyric has no service token; a freshly searched
    // result from the provider it was saved from does. They must still match.
    let body = "[00:01.000]line one\n[00:05.000]line two"
    let diskLoaded = makeLyrics(lrcBody: body)
    let searchResult = makeLyrics(lrcBody: body, service: "NetEase", serviceToken: "987")
    #expect(diskLoaded.isSameResult(as: searchResult))
}

@Test
func matchesWhenBothLackServiceAndBodyIdentical() {
    let body = "[00:01.000]a\n[00:02.500]b"
    #expect(makeLyrics(lrcBody: body).isSameResult(as: makeLyrics(lrcBody: body)))
}

@Test
func differsWhenBothLackServiceAndBodyDiffers() {
    let a = makeLyrics(lrcBody: "[00:01.000]a\n[00:02.000]b")
    let b = makeLyrics(lrcBody: "[00:01.000]a\n[00:09.000]b")
    #expect(!a.isSameResult(as: b))
}
