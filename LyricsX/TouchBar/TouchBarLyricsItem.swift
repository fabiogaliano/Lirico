import AppKit
import Combine
import LyricsXFoundation

class TouchBarLyricsItem: NSCustomTouchBarItem {
    private var lyricsTextField = KaraokeLabel(labelWithString: "")

    @objc dynamic var progressColor = #colorLiteral(red: 0.039, green: 0.518, blue: 1, alpha: 1)

    private var cancelBag = Set<AnyCancellable>()

    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func commonInit() {
        view = lyricsTextField
        customizationLabel = "Lyrics"
        LyricsSession.shared.$currentLyrics
            .combineLatest(LyricsSession.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay)
            .invoke(TouchBarLyricsItem.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
    }

    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard let lyrics = event.lyrics,
              let index = event.index else {
            DispatchQueue.main.async {
                self.lyricsTextField.stringValue = ""
                self.lyricsTextField.removeProgressAnimation()
            }
            return
        }
        let line = lyrics.lines[index]
        let (lyricsContent, _) = LineRenderer.render(
            line: line,
            lyricsLanguage: lyrics.metadata.language,
            translationLanguageCode: nil,
            convert: .mainLine
        )
        DispatchQueue.main.async {
            self.lyricsTextField.stringValue = lyricsContent
            if let timetag = line.attachments.timetag {
                let adjustedPos = PlaybackClock.shared.adjustedPlaybackTime
                let progress = timetag.tags.map { ($0.time + line.position - adjustedPos, $0.index) }
                self.lyricsTextField.setProgressAnimation(color: self.progressColor, progress: progress)
            }
        }
    }
}
