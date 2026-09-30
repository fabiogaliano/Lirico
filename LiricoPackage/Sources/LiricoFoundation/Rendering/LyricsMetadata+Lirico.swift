import Foundation

extension Lyrics.Metadata.Key {
    public static var localURL: Lyrics.Metadata.Key { Lyrics.Metadata.Key("localURL") }
    public static var title: Lyrics.Metadata.Key { Lyrics.Metadata.Key("title") }
    public static var artist: Lyrics.Metadata.Key { Lyrics.Metadata.Key("artist") }
    public static var needsPersist: Lyrics.Metadata.Key { Lyrics.Metadata.Key("needsPersist") }
    public static var persistenceAllowed: Lyrics.Metadata.Key { Lyrics.Metadata.Key("persistenceAllowed") }
    public static var language: Lyrics.Metadata.Key { Lyrics.Metadata.Key("language") }
}

extension Lyrics.Metadata {
    public var localURL: URL? {
        get { return data[.localURL] as? URL }
        set { data[.localURL] = newValue }
    }

    public var title: String? {
        get { return data[.title] as? String }
        set { data[.title] = newValue }
    }

    public var artist: String? {
        get { return data[.artist] as? String }
        set { data[.artist] = newValue }
    }

    public var needsPersist: Bool {
        get { return data[.needsPersist] as? Bool ?? false }
        set { data[.needsPersist] = newValue }
    }

    public var persistenceAllowed: Bool {
        get { return data[.persistenceAllowed] as? Bool ?? true }
        set { data[.persistenceAllowed] = newValue }
    }

    public var language: String? {
        get { return data[.language] as? String }
        set { data[.language] = newValue }
    }

    public var translationLanguages: [String] {
        return attachmentTags.compactMap { $0.translationLanguageCode }
    }
}

extension LyricsLine.Attachments.Tag {
    fileprivate var translationLanguageCode: String? {
        guard rawValue.hasPrefix("tr:") else {
            return nil
        }
        let code = rawValue.dropFirst(3)
        return code.isEmpty ? nil : String(code)
    }
}
