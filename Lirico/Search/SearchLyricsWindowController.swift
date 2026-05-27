import AppKit
import SwiftUI

final class SearchLyricsWindowController: NSWindowController {
    private let viewModel: SearchLyricsViewModel

    init(player: PlayerHandle, session: LyricsSession, pipeline: LyricsSearchPipeline, searchSettings: SearchSettings) {
        let viewModel = SearchLyricsViewModel(
            player: player,
            session: session,
            pipeline: pipeline,
            searchSettings: searchSettings
        )
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: SearchLyricsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = NSLocalizedString("Search Lyrics", comment: "window title")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
        super.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        viewModel.reloadFromCurrentTrack()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
