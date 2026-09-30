import AppKit
import Combine
import SwiftUI

final class SearchLyricsWindowController: NSWindowController {
    private let player: PlayerHandle
    private let viewModel: SearchLyricsViewModel
    private var trackChange: AnyCancellable?

    init(player: PlayerHandle, session: LyricsSession, pipeline: LyricsSearchPipeline, searchSettings: SearchSettings) {
        let viewModel = SearchLyricsViewModel(
            player: player,
            session: session,
            pipeline: pipeline,
            searchSettings: searchSettings
        )
        self.player = player
        self.viewModel = viewModel
        let hosting = NSHostingController(rootView: SearchLyricsView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = NSLocalizedString("Search Lyrics", comment: "window title")
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
        super.init(window: window)

        // Results are only meaningful for the track they were searched for, so follow the
        // player while the window is open instead of leaving stale results applicable.
        trackChange = player.currentTrackWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                guard let self, self.window?.isVisible == true else { return }
                self.viewModel.reload(for: track)
            }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        viewModel.reload(for: player.currentTrack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
