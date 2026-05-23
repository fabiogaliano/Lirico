import AppKit
import LyricsXFoundation
import TouchBarHelper
import OpenCC

class TouchBarLyricsController: TouchBarSystemModalController {
    static var shared: TouchBarLyricsController?

    private let player: PlayerHandle
    private let lyricsItem: TouchBarLyricsItem

    init(player: PlayerHandle, session: LyricsSession, clock: PlaybackClock) {
        self.player = player
        self.lyricsItem = TouchBarLyricsItem(identifier: .lyrics, session: session, clock: clock)
        super.init()
    }

    override func touchBarDidLoad() {
        touchBar?.defaultItemIdentifiers = [.currentArtwork, .fixedSpaceSmall, .playbackControl, .fixedSpaceSmall, .lyrics, .flexibleSpace, .otherItemsProxy]
        touchBar?.customizationIdentifier = .main
        touchBar?.customizationAllowedItemIdentifiers = [.currentArtwork, .playbackControl, .lyrics, .fixedSpaceSmall, .fixedSpaceLarge, .flexibleSpace, .otherItemsProxy]

        systemTrayItem = NSCustomTouchBarItem(identifier: .systemTrayItem)
        let trayImage = NSImage(systemSymbolName: "music.note", accessibilityDescription: "LyricsX") ?? NSImage()
        trayImage.isTemplate = true
        systemTrayItem?.view = NSButton(image: trayImage, target: self, action: #selector(present))

        lyricsItem.bind(\.progressColor, withUnmatchedDefaultName: .desktopLyricsProgressColor)

        observeNotification(name: NSApplication.willBecomeActiveNotification) { [weak self] _ in
            guard let self = self else { return }
            self.removeFromControlStrip()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                NSApp.touchBar = self.touchBar
            }
        }

        observeNotification(name: NSApplication.didResignActiveNotification) { [weak self] _ in
            guard let self = self else { return }
            NSApp.touchBar = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                self.showInControlStrip()
            }
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .lyrics:
            return lyricsItem
        case .playbackControl:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let playbackVC = TouchBarPlaybackControlViewController()
            playbackVC.player = player
            item.viewController = playbackVC
            item.customizationLabel = "Playback Control"
            return item
        case .currentArtwork:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let artworkVC = TouchBarArtworkViewController()
            artworkVC.player = player
            item.viewController = artworkVC
            item.customizationLabel = "Artwork"
            return item
        default:
            return nil
        }
    }
}

extension NSTouchBarItem.Identifier {
    fileprivate static let lyrics = NSTouchBarItem.Identifier("com.fabiogaliano.LyricsX.touchBar.lyrics")
    fileprivate static let currentArtwork = NSTouchBarItem.Identifier("com.fabiogaliano.LyricsX.touchBar.currentArtwork")
    fileprivate static let playbackControl = NSTouchBarItem.Identifier("com.fabiogaliano.LyricsX.touchBar.playbackControl")

    fileprivate static let systemTrayItem = NSTouchBarItem.Identifier("com.fabiogaliano.LyricsX.touchBar.systemTrayItem")
}

extension NSTouchBar.CustomizationIdentifier {
    static let main = NSTouchBar.CustomizationIdentifier("com.fabiogaliano.LyricsX.touchBar.customization.main")
}
