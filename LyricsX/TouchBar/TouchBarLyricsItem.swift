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
        LyricsSession.shared.displayCoordinator.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.render(snapshot)
            }
            .store(in: &cancelBag)
    }

    // Touch Bar historically ignores `disableLyricsWhenPaused`, so we look only
    // at `snapshot.line` here instead of `snapshot.isLive`.
    private func render(_ snapshot: LyricsDisplaySnapshot) {
        guard let line = snapshot.line else {
            lyricsTextField.stringValue = ""
            lyricsTextField.removeProgressAnimation()
            return
        }
        lyricsTextField.stringValue = line.primaryText
        if let timetag = line.line.attachments.timetag {
            let adjustedPos = PlaybackClock.shared.adjustedPlaybackTime
            let progress = timetag.tags.map { ($0.time + line.line.position - adjustedPos, $0.index) }
            lyricsTextField.setProgressAnimation(color: progressColor, progress: progress)
        }
    }
}
