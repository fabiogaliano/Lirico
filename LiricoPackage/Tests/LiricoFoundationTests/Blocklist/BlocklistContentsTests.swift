import Testing
@testable import LiricoFoundation

@Suite("Blocklist contents")
struct BlocklistContentsTests {
    @Test func blockingATrackRecordsItsName() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "SS26", artist: "Artist")

        #expect(contents.isBlocked(trackID: "t1"))
        #expect(contents.entries == [BlockedEntry(kind: .track(id: "t1"), title: "SS26", artist: "Artist")])
    }

    @Test func blockingTheSameTrackTwiceKeepsOneEntry() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "Old", artist: nil)
        contents.block(trackID: "t1", title: "New", artist: "Artist")

        #expect(contents.trackIDs == ["t1"])
        #expect(contents.entries == [BlockedEntry(kind: .track(id: "t1"), title: "New", artist: "Artist")])
    }

    @Test func tracksBlockedBeforeNamesWereRecordedHaveNoName() {
        let contents = BlocklistContents(trackIDs: ["legacy"], trackNames: [:], albums: [])

        #expect(contents.entries == [BlockedEntry(kind: .track(id: "legacy"), title: nil, artist: nil)])
    }

    @Test func blockingTheSameAlbumTwiceKeepsOneEntry() {
        var contents = BlocklistContents()
        contents.block(album: "Album")
        contents.block(album: "Album")

        #expect(contents.albums == ["Album"])
        #expect(contents.isBlocked(album: "Album"))
    }

    @Test func entriesListSongsThenAlbumsNewestFirst() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "First", artist: nil)
        contents.block(album: "Album A")
        contents.block(trackID: "t2", title: "Second", artist: nil)
        contents.block(album: "Album B")

        #expect(contents.entries.map(\.kind) == [
            .track(id: "t2"), .track(id: "t1"), .album("Album B"), .album("Album A"),
        ])
    }

    @Test func removingATrackEntryForgetsItsName() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "SS26", artist: "Artist")
        contents.block(album: "Album")

        contents.remove(.track(id: "t1"))

        #expect(!contents.isBlocked(trackID: "t1"))
        #expect(contents.trackNames.isEmpty)
        #expect(contents.isBlocked(album: "Album"))
    }

    @Test func removingAnAlbumEntryLeavesTracksBlocked() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "SS26", artist: nil)
        contents.block(album: "Album")

        contents.remove(.album("Album"))

        #expect(!contents.isBlocked(album: "Album"))
        #expect(contents.isBlocked(trackID: "t1"))
    }

    @Test func unblockingATrackAlsoLiftsItsAlbum() {
        var contents = BlocklistContents()
        contents.block(trackID: "t1", title: "SS26", artist: nil)
        contents.block(album: "Album")
        contents.block(album: "Other")

        contents.unblock(trackID: "t1", album: "Album")

        #expect(!contents.isBlocked(trackID: "t1"))
        #expect(!contents.isBlocked(album: "Album"))
        #expect(contents.isBlocked(album: "Other"))
    }

    @Test func duplicateIDsFromOlderVersionsAreAllRemoved() {
        var contents = BlocklistContents(trackIDs: ["t1", "t2", "t1"], trackNames: [:], albums: ["A", "A"])

        contents.remove(.track(id: "t1"))
        contents.remove(.album("A"))

        #expect(contents.trackIDs == ["t2"])
        #expect(contents.albums.isEmpty)
    }

    @Test func duplicateIDsFromOlderVersionsAreListedOnce() {
        let contents = BlocklistContents(trackIDs: ["t1", "t1"], trackNames: [:], albums: ["A", "A"])

        #expect(contents.entries.map(\.kind) == [.track(id: "t1"), .album("A")])
    }
}
