import AppKit
import UIFoundation

final class SearchLyricsWindowController: NSWindowController {
    let viewController: SearchLyricsViewController

    init(player: PlayerHandle, session: LyricsSession, pipeline: LyricsSearchPipeline) {
        let viewController = SearchLyricsViewController.create()
        viewController.configure(player: player, session: session, pipeline: pipeline)
        self.viewController = viewController
        let window = NSWindow(contentViewController: viewController)
        window.title = NSLocalizedString("Search Lyrics", comment: "window title")
        super.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        viewController.reloadKeyword()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
