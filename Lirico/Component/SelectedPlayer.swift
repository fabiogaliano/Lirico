import Foundation
import MusicPlayer
import GenericID
import Combine
import LiricoFoundation

extension MusicPlayers {
    /// Unchecked because all of its mutable state is confined to `stateQueue`.
    final class Selected: Agent, @unchecked Sendable {
        static let shared = MusicPlayers.Selected()

        private var defaultsObservation: DefaultsObservation?

        private var manualUpdateObservation: AnyCancellable?

        private let settings = PlayerSettings()

        /// Auto mode's candidates. Every one is watched, not just the chosen one: upstream
        /// `NowPlaying` only re-evaluated when its current pick changed, so starting another
        /// player while the previous one sat paused went unnoticed.
        private var autoPlayers: [MusicPlayers.Scriptable] = []
        private var autoSelectionObservation: AnyCancellable?

        /// Every change to this object's state happens here. The triggers arrive on main (the
        /// Follow setting), on the players' queue (state changes) and on this queue (auto
        /// selection); left unserialized, a late auto pick could overwrite the system-wide
        /// player the user just switched to, or two polls could start and one never stop.
        private let stateQueue = DispatchQueue(label: "Lirico.SelectedPlayer")

        private let manualUpdateInterval: TimeInterval = 1.0
        private var scheduleCanceller: Cancellable?

        override init() {
            super.init()
            stateQueue.sync {
                selectPlayer()
                scheduleManualUpdate()
            }
            self.defaultsObservation = defaults.observe(keys: [.useSystemWideNowPlaying, .systemWideNowPlayingAppList]) { [weak self] in
                self?.stateQueue.async { [weak self] in self?.selectPlayer() }
            }
            self.manualUpdateObservation = playbackStateWillChange
                .receive(on: stateQueue)
                .sink { [weak self] state in
                    if state.isPlaying {
                        self?.scheduleManualUpdate()
                    } else {
                        self?.scheduleCanceller?.cancel()
                    }
                }
        }

        private func selectPlayer() {
            if settings.useSystemWideNowPlaying {
                stopAutoSelection()
                designatedPlayer = MusicPlayers.SystemMedia(allowsApplicationBundleIdentifiers: settings.systemWideNowPlayingAppList)
            } else {
                startAutoSelection()
            }
        }

        private func startAutoSelection() {
            autoPlayers = MusicPlayerName.scriptableCases.compactMap(MusicPlayers.Scriptable.init)
            chooseAutoPlayer()
            // `objectWillChange` fires before the new state is stored, on the players' own queue.
            // A short debounce runs the choice after the assignment lands, and collapses the
            // track + state pair a player emits together into one decision.
            autoSelectionObservation = Publishers.MergeMany(autoPlayers.map(\.objectWillChange))
                .debounce(for: .milliseconds(100), scheduler: stateQueue)
                .sink { [weak self] _ in self?.chooseAutoPlayer() }
        }

        private func stopAutoSelection() {
            autoSelectionObservation = nil
            autoPlayers = []
        }

        private func chooseAutoPlayer() {
            // A debounced choice can already be queued when the user switches to system-wide.
            guard !autoPlayers.isEmpty else { return }
            let current = designatedPlayer as? MusicPlayers.Scriptable
            let chosen = ScriptablePlayers.autoChoice(
                current: current.flatMap { current in autoPlayers.firstIndex { $0 === current } },
                states: autoPlayers.map(\.playbackState)
            ).map { autoPlayers[$0] }
            if chosen !== current {
                designatedPlayer = chosen
            }
        }

        private func scheduleManualUpdate() {
            scheduleCanceller?.cancel()
            let i: DispatchQueue.SchedulerTimeType.Stride = .seconds(manualUpdateInterval)
            scheduleCanceller = stateQueue.schedule(
                after: stateQueue.now.advanced(by: i), interval: i, tolerance: i * 0.1, options: nil
            ) { [unowned self] in
                self.designatedPlayer?.updatePlayerState()
            }
        }
    }
}
