import AppKit
import Combine
import Regex
import OpenCC
import MusicPlayer
import LyricsXFoundation

class AppController: NSObject {
    static var shared: AppController!

    var lyricsManager: LyricsProvider
    private let player: PlayerHandle

    @Published var currentLyrics: Lyrics? {
        willSet {
            willChangeValue(forKey: "lyricsOffset")
            currentLineIndex = nil
        }
        didSet {
            didChangeValue(forKey: "lyricsOffset")
            scheduleCurrentLineCheck()
        }
    }

    @Published var currentLineIndex: Int?

    var searchRequest: LyricsSearchRequest?
    var searchTask: Task<Void, Never>?

    private var cancelBag = Set<AnyCancellable>()

    @objc dynamic var lyricsOffset: Int {
        get {
            return currentLyrics?.offset ?? 0
        }
        set {
            currentLyrics?.offset = newValue
            currentLyrics?.metadata.needsPersist = true
            scheduleCurrentLineCheck()
        }
    }

    init(player: PlayerHandle) {
        self.lyricsManager = LyricsProviders.Group()
        self.player = player
        super.init()
        player.currentTrackWillChange
            .signal()
            .receive(on: DispatchQueue.lyricsDisplay)
            .invoke(AppController.currentTrackChanged, weaklyOn: self)
            .store(in: &cancelBag)

        PlaybackClock.shared.currentLineIndex
            .sink { [weak self] index in self?.currentLineIndex = index }
            .store(in: &cancelBag)

        workspaceNC.publisher(for: NSWorkspace.didTerminateApplicationNotification, object: nil)
            .sink { notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let bundleID = application.bundleIdentifier
                if defaults[.launchAndQuitWithPlayer], player.designatedPlayerBundleID == bundleID {
                    NSApplication.shared.terminate(self)
                }
            }.store(in: &cancelBag)
        // Defer the initial sync: setting currentLyrics here would re-enter
        // AppController.shared via PlaybackClock.tick() while dispatch_once is
        // still in flight, which libdispatch traps as recursive locking.
        DispatchQueue.main.async { [weak self] in
            self?.currentTrackChanged()
        }

        Task {
            try await updateLyricsManager()
        }
    }

    @MainActor
    func updateLyricsManager() async throws {
        let services: [LyricsProviders.Service] = LyricsProviders.Service.noAuthenticationRequiredServices

        var providers: [LyricsProvider] = []
        for service in services {
            providers.append(service.create())
        }

        // Add Musixmatch provider with saved token if available
        if let token = defaults[.musixmatchToken], !token.isEmpty {
            let musixmatchProvider = LyricsProviders.Musixmatch(usertoken: token)
            providers.append(musixmatchProvider)
        }

        lyricsManager = LyricsProviders.Group(providers: providers)
    }

    func scheduleCurrentLineCheck() {
        PlaybackClock.shared.tick()
    }

    func writeToiTunes(overwrite: Bool) {
        guard player.name == .appleMusic,
              let currentLyrics = currentLyrics,
              let sbTrack = player.currentTrack?.originalTrack,
              overwrite || (sbTrack.value(forKey: "lyrics") as! String?)?.isEmpty != false else {
            return
        }

        let content: String
        if defaults[.writeiTunesConvertToPlainLRC] {
            // For plain LRC export, preserve the legacy LRC formatting but still respect
            // the Chinese conversion setting for consistency with the non-plain branch.
            var legacy = currentLyrics.legacyDescription
            if let converter = ChineseConverter.shared,
               currentLyrics.metadata.language?.hasPrefix("zh") == true {
                legacy = converter.convert(legacy)
            }
            // Note: translations are intentionally not appended for plain LRC export,
            // even when `writeiTunesWithTranslation` is enabled, to keep the legacy
            // LRC output single-line per timestamp.
            content = legacy
        } else {
            // TODO: tagged translation
            let translationCode = defaults[.writeiTunesWithTranslation]
                ? currentLyrics.metadata.translationLanguages.first
                : nil
            content = currentLyrics.lines.map { line -> String in
                let (main, translation) = LineRenderer.render(
                    line: line,
                    lyricsLanguage: currentLyrics.metadata.language,
                    translationLanguageCode: translationCode,
                    convert: .all
                )
                if let translation {
                    return main + "\n" + translation
                }
                return main
            }.joined(separator: "\n")
        }
        // swiftlint:disable:next force_try
        let regex = Regex(#"\n{3,}"#)
        let replaced = content.replacingMatches(of: regex, with: "\n\n")
        sbTrack.setValue(replaced, forKey: "lyrics")
    }

    func currentTrackChanged() {
        if currentLyrics?.metadata.needsPersist == true {
            currentLyrics?.persist()
        }
        currentLyrics = nil
        currentLineIndex = nil
        searchTask?.cancel()
        guard let track = player.currentTrack else {
            return
        }
        // FIXME: deal with optional value
        let title = track.title ?? ""
        let artist = track.artist ?? ""

        guard !SearchBlocklist.isBlocked(track: track) else {
            return
        }

        switch LocalLyricsLoader.load(track: track, title: title, artist: artist) {
        case .found(let lyrics):
            currentLyrics = lyrics
            return
        case .foundPartial(let lyrics):
            currentLyrics = lyrics
        case .none:
            break
        }

        if let album = track.album, SearchBlocklist.isBlocked(album: album) {
            return
        }

        let duration = track.duration ?? 0
        let request = LyricsSearchRequest(searchTerm: .info(title: title, artist: artist), duration: duration, limit: 5)
        searchRequest = request
        searchTask = Task { @MainActor in
            do {
                let window = defaults[.lyricsPriorityWindow] ?? 5
                var collector = LyricsSelector.shared.makeCollector(window: window)

                search: for try await lyrics in lyricsManager.lyrics(for: request) {
                    switch collector.nextDecision() {
                    case .accept:
                        let before = currentLyrics
                        lyricsReceived(lyrics: lyrics)
                        if currentLyrics !== before {
                            collector.notifyAccepted()
                        }
                    case .stop:
                        break search
                    }
                }

                if defaults[.writeToiTunesAutomatically] {
                    writeToiTunes(overwrite: true)
                }
            } catch is CancellationError {
                // Search was cancelled due to track change
            } catch {
                print("Failed to fetch lyrics: \(error.localizedDescription)")
            }
        }
    }

    // MARK: LyricsSourceDelegate

    func lyricsReceived(lyrics: Lyrics) {
        guard let req = searchRequest,
              lyrics.metadata.request == req,
              let track = player.currentTrack else {
            return
        }
        if defaults[.strictSearchEnabled], !lyrics.isMatched() {
            return
        }
        if !LyricsSelector.shared.hasHigherPriority(lyrics, over: currentLyrics) {
            return
        }

        lyrics.associateWithTrack(track)
        LyricsPreparer.prepare(lyrics)
        lyrics.metadata.needsPersist = true
        currentLyrics = lyrics
    }
}

extension AppController {
    func importLyrics(_ lyricsString: String) throws {
        guard let lrc = Lyrics(lyricsString) else {
            let errorInfo = [
                NSLocalizedDescriptionKey: "Invalid lyric file",
                NSLocalizedRecoverySuggestionErrorKey: "Please try another one.",
            ]
            let error = NSError(domain: lyricsXErrorDomain, code: 0, userInfo: errorInfo)
            throw error
        }
        guard let track = player.currentTrack else {
            let errorInfo = [
                NSLocalizedDescriptionKey: "No music playing",
                NSLocalizedRecoverySuggestionErrorKey: "Play a music and try again.",
            ]
            let error = NSError(domain: lyricsXErrorDomain, code: 0, userInfo: errorInfo)
            throw error
        }
        lrc.metadata.title = track.title
        lrc.metadata.artist = track.artist
        LyricsPreparer.prepare(lrc)
        lrc.metadata.needsPersist = true
        currentLyrics = lrc
        SearchBlocklist.unblock(track: track)
        SearchBlocklist.unblock(album: track.album ?? "")
    }
}
