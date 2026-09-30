import AppKit
import LiricoFoundation
import MusicPlayer

extension MusicPlayerName {
    var icon: NSImage {
        switch self {
        case .appleMusic: return #imageLiteral(resourceName: "iTunes_icon")
        case .spotify: return #imageLiteral(resourceName: "spotify_icon")
        case .vox: return #imageLiteral(resourceName: "vox_icon")
        case .audirvana: return #imageLiteral(resourceName: "audirvana_icon")
        case .swinsian: return #imageLiteral(resourceName: "swinsian_icon")
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
