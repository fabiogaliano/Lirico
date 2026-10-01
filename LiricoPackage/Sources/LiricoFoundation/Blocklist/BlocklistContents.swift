/// The songs and albums Lirico won't search lyrics for, in the shape they're stored in defaults.
///
/// Tracks are identified by the player's opaque track ID, so their title and artist are
/// kept alongside to make the list readable. Tracks blocked before names were recorded
/// have no name, and older versions could store the same ID or album more than once.
public struct BlocklistContents: Equatable, Sendable {
    public static let titleKey = "title"
    public static let artistKey = "artist"

    public private(set) var trackIDs: [String]
    public private(set) var trackNames: [String: [String: String]]
    public private(set) var albums: [String]

    public init(trackIDs: [String] = [], trackNames: [String: [String: String]] = [:], albums: [String] = []) {
        self.trackIDs = trackIDs
        self.trackNames = trackNames
        self.albums = albums
    }

    public func isBlocked(trackID: String) -> Bool {
        trackIDs.contains(trackID)
    }

    public func isBlocked(album: String) -> Bool {
        albums.contains(album)
    }

    public mutating func block(trackID: String, title: String?, artist: String?) {
        trackIDs.removeAll { $0 == trackID }
        trackIDs.append(trackID)
        var name: [String: String] = [:]
        name[Self.titleKey] = title
        name[Self.artistKey] = artist
        trackNames[trackID] = name.isEmpty ? nil : name
    }

    public mutating func block(album: String) {
        albums.removeAll { $0 == album }
        albums.append(album)
    }

    /// Lifts every block that stops a track from being searched: its own and its album's.
    public mutating func unblock(trackID: String, album: String?) {
        remove(.track(id: trackID))
        if let album {
            remove(.album(album))
        }
    }

    public mutating func remove(_ kind: BlockedEntry.Kind) {
        switch kind {
        case .track(let id):
            trackIDs.removeAll { $0 == id }
            trackNames[id] = nil
        case .album(let name):
            albums.removeAll { $0 == name }
        }
    }

    /// Songs, then albums, each most recently blocked first.
    public var entries: [BlockedEntry] {
        let tracks = uniqueNewestFirst(trackIDs).map { id in
            BlockedEntry(kind: .track(id: id), title: trackNames[id]?[Self.titleKey], artist: trackNames[id]?[Self.artistKey])
        }
        let albumEntries = uniqueNewestFirst(albums).map { BlockedEntry(kind: .album($0), title: $0, artist: nil) }
        return tracks + albumEntries
    }

    private func uniqueNewestFirst(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.reversed().filter { seen.insert($0).inserted }
    }
}

public struct BlockedEntry: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case track(id: String)
        case album(String)
    }

    public let kind: Kind
    /// The track's title or the album's name; nil for a track blocked before names were recorded.
    public let title: String?
    public let artist: String?

    public var id: Kind { kind }

    public init(kind: Kind, title: String?, artist: String?) {
        self.kind = kind
        self.title = title
        self.artist = artist
    }
}
