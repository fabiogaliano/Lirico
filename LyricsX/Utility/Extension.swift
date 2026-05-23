import AppKit
import LyricsXFoundation
import MusicPlayer

extension MusicPlayerName {
    init?(index: Int) {
        switch index {
        case 0: self = .appleMusic
        case 1: self = .spotify
        case 2: self = .vox
        case 3: self = .audirvana
        case 4: self = .swinsian
        default: return nil
        }
    }

    var icon: NSImage {
        switch self {
        case .appleMusic: return #imageLiteral(resourceName: "iTunes_icon")
        case .spotify: return #imageLiteral(resourceName: "spotify_icon")
        case .vox: return #imageLiteral(resourceName: "vox_icon")
        case .audirvana: return #imageLiteral(resourceName: "audirvana_icon")
        case .swinsian: return #imageLiteral(resourceName: "swinsian_icon")
        }
    }

    /// Whether this player can expose a local file URL for the current track,
    /// so the loader can look for an `.lrcx`/`.lrc` sitting next to the audio file.
    /// Players that don't (streaming-only or no scripting bridge for `location`)
    /// must have the "Load lyrics beside track" option disabled in preferences.
    var supportsBesideTrackLyrics: Bool {
        switch self {
        case .appleMusic, .vox: return true
        case .spotify, .audirvana, .swinsian: return false
        }
    }
}

extension MusicTrack {
    var lyrics: String? {
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("lyrics"))) else {
            return nil
        }
        return originalTrack.value(forKey: "lyrics") as? String
    }

    func setLyrics(_ lyrics: String) {
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("setLyrics:"))) else {
            return
        }
        originalTrack.setValue(lyrics, forKey: "lyrics")
    }
    
    var localFileURL: URL? {
        if let url = fileURL {
            return url
        }
        guard let originalTrack = originalTrack,
              originalTrack.responds(to: Selector(("location"))) else {
            return nil
        }
        return originalTrack.value(forKey: "location") as? URL
    }
}

extension NSFont {
    convenience init?(name fontName: String, size fontSize: CGFloat, fallback fallbackNames: [String]) {
        let cascadeList = fallbackNames.compactMap {
            NSFontDescriptor(name: $0, size: fontSize)
                .matchingFontDescriptor(withMandatoryKeys: [.name, .size])
        }
        let descriptor = NSFontDescriptor(fontAttributes: [.name: fontName, .cascadeList: cascadeList])
        self.init(descriptor: descriptor, size: fontSize)
    }
}

extension UserDefaults {
    var desktopLyricsFont: NSFont {
        return NSFont(
            name: self[.desktopLyricsFontName],
            size: CGFloat(self[.desktopLyricsFontSize]),
            fallback: self[.desktopLyricsFontNameFallback]
        )
            ?? NSFont.systemFont(ofSize: CGFloat(self[.desktopLyricsFontSize]))
    }

    var lyricsWindowFont: NSFont {
        return NSFont(
            name: defaults[.lyricsWindowFontName],
            size: CGFloat(defaults[.lyricsWindowFontSize])
        )
            ?? NSFont.labelFont(ofSize: CGFloat(defaults[.lyricsWindowFontSize]))
    }
}

extension Lyrics {
    func associateWithTrack(_ track: MusicTrack) {
        metadata.title = track.title
        metadata.artist = track.artist
    }
}

extension Lyrics {
    var adjustedOffset: Int {
        return offset + defaults[.globalLyricsOffset]
    }

    var adjustedTimeDelay: TimeInterval {
        return TimeInterval(adjustedOffset) / 1000
    }
}

extension NSImage {
    func scaled(to size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            let srcRect = NSRect(origin: .zero, size: self.size)
            self.draw(in: rect, from: srcRect, operation: .copy, fraction: 1)
            return true
        }
    }
}
