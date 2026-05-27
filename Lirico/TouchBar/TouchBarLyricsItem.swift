import AppKit
import Combine
import LiricoFoundation

class TouchBarLyricsItem: NSCustomTouchBarItem {
    private var lyricsTextField = KaraokeLabel(labelWithString: "")

    @objc dynamic var progressColor = #colorLiteral(red: 0.039, green: 0.518, blue: 1, alpha: 1)

    private let session: LyricsSession
    private let clock: PlaybackClock

    private var cancelBag = Set<AnyCancellable>()

    init(identifier: NSTouchBarItem.Identifier, session: LyricsSession, clock: PlaybackClock) {
        self.session = session
        self.clock = clock
        super.init(identifier: identifier)
        view = lyricsTextField
        customizationLabel = "Lyrics"
        session.displayCoordinator.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.render(snapshot)
            }
            .store(in: &cancelBag)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; TouchBarLyricsItem is constructed programmatically.")
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
            let adjustedPos = clock.adjustedPlaybackTime
            let progress = timetag.tags.map { ($0.time + line.line.position - adjustedPos, $0.index) }
            lyricsTextField.setProgressAnimation(color: progressColor, progress: progress)
        }
    }
}
