import Foundation
import MusicPlayer
import GenericID
import Combine

extension MusicPlayers {
    final class Selected: Agent {
        static let shared = MusicPlayers.Selected()

        private var defaultsObservation: DefaultsObservation?

        private var manualUpdateObservation: AnyCancellable?

        private let settings = PlayerSettings()

        /// Auto mode's candidates. Every one is watched, not just the chosen one: upstream
        /// `NowPlaying` only re-evaluated when its current pick changed, so starting another
        /// player while the previous one sat paused went unnoticed.
        private var autoPlayers: [MusicPlayers.Scriptable] = []
        private var autoSelectionObservation: AnyCancellable?
        private let autoSelectionQueue = DispatchQueue(label: "Lirico.AutoPlayerSelection")

        var manualUpdateInterval: TimeInterval = 1.0 {
            didSet {
                scheduleManualUpdate()
            }
        }

        override init() {
            super.init()
            selectPlayer()
            scheduleManualUpdate()
            self.defaultsObservation = defaults.observe(keys: [.preferredPlayerIndex, .useSystemWideNowPlaying, .systemWideNowPlayingAppList]) { [weak self] in
                self?.selectPlayer()
            }
            self.manualUpdateObservation = playbackStateWillChange.sink { [weak self] state in
                if state.isPlaying {
                    self?.scheduleManualUpdate()
                } else {
                    self?.scheduleCanceller?.cancel()
                }
            }
        }

        private func selectPlayer() {
            let idx = settings.preferredPlayerIndex
            if idx == -1 {
                if settings.useSystemWideNowPlaying {
                    designatedPlayer = MusicPlayers.SystemMedia(allowsApplicationBundleIdentifiers: settings.systemWideNowPlayingAppList)
                    stopAutoSelection()
                } else {
                    startAutoSelection()
                }
            } else {
                stopAutoSelection()
                designatedPlayer = MusicPlayerName(index: idx).flatMap(MusicPlayers.Scriptable.init)
            }
        }

        private func startAutoSelection() {
            autoPlayers = MusicPlayerName.scriptableCases.compactMap(MusicPlayers.Scriptable.init)
            chooseAutoPlayer()
            // `objectWillChange` fires before the new state is stored, on the players' own queue.
            // A short debounce runs the choice after the assignment lands, and collapses the
            // track + state pair a player emits together into one decision.
            autoSelectionObservation = Publishers.MergeMany(autoPlayers.map(\.objectWillChange))
                .debounce(for: .milliseconds(100), scheduler: autoSelectionQueue)
                .sink { [weak self] _ in self?.chooseAutoPlayer() }
        }

        private func stopAutoSelection() {
            autoSelectionObservation = nil
            autoPlayers = []
        }

        /// Stick with a player while it plays; otherwise follow whichever one is playing, then
        /// whichever is paused, so pausing briefly never hands lyrics to another app.
        private func chooseAutoPlayer() {
            let current = designatedPlayer as? MusicPlayers.Scriptable
            let chosen: MusicPlayers.Scriptable?
            if let current, autoPlayers.contains(where: { $0 === current }), current.playbackState.isPlaying {
                chosen = current
            } else if let playing = autoPlayers.first(where: { $0.playbackState.isPlaying }) {
                chosen = playing
            } else if let current, autoPlayers.contains(where: { $0 === current }), current.playbackState != .stopped {
                chosen = current
            } else {
                chosen = autoPlayers.first { $0.playbackState != .stopped }
            }
            if chosen !== current {
                designatedPlayer = chosen
            }
        }

        private var scheduleCanceller: Cancellable?
        func scheduleManualUpdate() {
            scheduleCanceller?.cancel()
            guard manualUpdateInterval > 0 else { return }
            let q = DispatchQueue.global()
            let i: DispatchQueue.SchedulerTimeType.Stride = .seconds(manualUpdateInterval)
            scheduleCanceller = q.schedule(after: q.now.advanced(by: i), interval: i, tolerance: i * 0.1, options: nil) { [unowned self] in
                self.designatedPlayer?.updatePlayerState()
            }
        }
    }
}

extension MusicPlayers.SystemMedia: Then {}
