import AppKit
import Combine
import MusicPlayer

class TouchBarArtworkViewController: NSViewController {
    private let player: PlayerHandle

    let artworkView = NSImageView()

    private var cancelBag = Set<AnyCancellable>()

    init(player: PlayerHandle) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported; TouchBarArtworkViewController is constructed programmatically.")
    }

    override func loadView() {
        view = artworkView
    }

    override func viewDidLoad() {
        player.currentTrackWillChange
            .signal()
            .receive(on: DispatchQueue.main)
            .invoke(TouchBarArtworkViewController.updateArtworkImage, weaklyOn: self)
            .store(in: &cancelBag)
        updateArtworkImage()
    }

    func updateArtworkImage() {
        if let image = player.currentTrack?.artwork ?? player.name?.icon {
            let size = CGSize(width: 30, height: 30)
            artworkView.image = NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }
        } else {
            // TODO: Placeholder
            artworkView.image = nil
        }
    }
}
