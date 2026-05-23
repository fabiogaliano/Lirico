import AppKit
import LaunchAtLogin
import MusicPlayer
import ServiceManagement
import SwiftUI

// MARK: - General Preferences View

struct GeneralPreferencesView: View {
    // Player selection — -1 = auto, 0-4 = specific player (MusicPlayerName(index:))
    @AppStorage("PreferredPlayerIndex") private var preferredPlayerIndex = 1

    // Lyrics saving path popup index — 0 = default, 1 = custom
    @AppStorage("LyricsSavingPathPopUpIndex") private var savingPathPopUpIndex = 0

    // Search & Display
    @AppStorage("GlobalLyricsOffset") private var globalLyricsOffset = 0
    @AppStorage("StrictSearchEnabled") private var strictSearchEnabled = false
    @AppStorage("PreferBilingualLyrics") private var preferBilingualLyrics = false
    @AppStorage("ChineseConversionIndex") private var chineseConversionIndex = 0
    @AppStorage("CombinedMenubarLyrics") private var combinedMenubarLyrics = false
    @AppStorage("HideMenuBarItems") private var hideMenuBarItems = false

    // Player-dependent settings — written back via the settings structs so the
    // side effects (constraint enforcement) run inside the onChange handlers.
    @AppStorage("LaunchAndQuitWithPlayer") private var launchAndQuitWithPlayer = false
    @AppStorage("LoadLyricsBesideTrack") private var loadLyricsBesideTrack = false

    // Custom saving path display name — derived from bookmark on appear, updated
    // after the user picks a new directory via NSOpenPanel.
    @State private var customDirectoryName: String = ""

    // Language picker — index 0 = system, 2+ = specific localization
    @State private var languagePickerIndex = 0

    private let persistenceSettings = PersistenceSettings()
    private let playerSettings = PlayerSettings()

    // MARK: - Derived state

    private var selectedPlayer: MusicPlayerName? {
        MusicPlayerName(index: preferredPlayerIndex)
    }

    // "Launch and quit with player" is only meaningful when a specific player is chosen.
    private var canLaunchWithPlayer: Bool { selectedPlayer != nil }

    // "Load lyrics beside track" is only meaningful for players that expose a file URL.
    private var canLoadBesideTrack: Bool { selectedPlayer?.supportsBesideTrackLyrics ?? true }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                musicPlayerSection
                lyricsFilesSection
                searchDisplaySection
                languageSection
            }
            .padding(20)
        }
        .onAppear(perform: loadInitialState)
    }

    // MARK: - Sections

    private var musicPlayerSection: some View {
        SettingsSection(title: "Music Player") {
            playerPicker
            // Registers/unregisters LyricsXHelper as a login item AND persists the
            // LaunchAndQuitWithPlayer setting. Disabled when "Auto" is selected because
            // there is no designated player to follow.
            Toggle("Auto launch & quit with music player", isOn: $launchAndQuitWithPlayer)
                .disabled(!canLaunchWithPlayer)
                .onChange(of: launchAndQuitWithPlayer) { enabled in
                    if !SMLoginItemSetEnabled(lyricsXHelperIdentifier as CFString, enabled) {
                        log("Failed to set login item enabled")
                    }
                }
                .onChange(of: canLaunchWithPlayer) { enabled in
                    if !enabled {
                        launchAndQuitWithPlayer = false
                        playerSettings.launchAndQuitWithPlayer = false
                        if !SMLoginItemSetEnabled(lyricsXHelperIdentifier as CFString, false) {
                            log("Failed to set login item enabled")
                        }
                    }
                }
            // Controls whether the main LyricsX app itself launches at system login,
            // independently of any music player. Mirrors the storyboard's "Launch at login"
            // checkbox which was bound to LaunchAtLogin.kvo.isEnabled.
            LaunchAtLogin.Toggle("Launch at login")
        }
    }

    private var lyricsFilesSection: some View {
        SettingsSection(title: "Lyrics Files") {
            savingPathRow
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.open(persistenceSettings.storageDirectory().url)
                }
                Spacer()
            }
            Toggle("Load lyrics beside track", isOn: $loadLyricsBesideTrack)
                .disabled(!canLoadBesideTrack)
                .onChange(of: canLoadBesideTrack) { enabled in
                    if !enabled {
                        persistenceSettings.shouldLoadLyricsBesideTrack = false
                        loadLyricsBesideTrack = false
                    }
                }
        }
    }

    private var searchDisplaySection: some View {
        SettingsSection(title: "Search & Display") {
            SettingsRow(label: "Global lyrics offset (ms)") {
                HStack(spacing: 4) {
                    TextField("", value: $globalLyricsOffset, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Stepper("", value: $globalLyricsOffset, step: 100)
                        .labelsHidden()
                }
            }
            Toggle("Strict search", isOn: $strictSearchEnabled)
            Toggle("Prefer bilingual lyrics", isOn: $preferBilingualLyrics)
            SettingsRow(label: "Auto Chinese conversion") {
                Picker("", selection: $chineseConversionIndex) {
                    Text("No Conversion").tag(0)
                    Text("Simplified Chinese").tag(1)
                    Text("Traditional Chinese").tag(2)
                    Text("Traditional Chinese (Taiwan)").tag(3)
                    Text("Traditional Chinese (Hong Kong)").tag(4)
                }
                .labelsHidden()
                .frame(width: 230)
            }
            Toggle("Combined menubar lyrics", isOn: $combinedMenubarLyrics)
            Toggle("Hide menu bar items", isOn: $hideMenuBarItems)
        }
    }

    private var languageSection: some View {
        SettingsSection(title: "Language") {
            SettingsRow(label: "Language") {
                Picker("", selection: $languagePickerIndex) {
                    Text("System").tag(0)
                    ForEach(Array(localizations.enumerated()), id: \.offset) { offset, lan in
                        Text(localizedLanguageName(for: lan)).tag(offset + 2)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: languagePickerIndex) { idx in
                    applyLanguageSelection(idx)
                }
            }
            Button("Help Translate…") {
                NSWorkspace.shared.open(crowdinProjectURL)
            }
        }
    }

    // MARK: - Complex sub-views

    @ViewBuilder private var playerPicker: some View {
        Picker("Preferred player", selection: $preferredPlayerIndex) {
            Text("Auto").tag(-1)
            Divider()
            Text("Apple Music").tag(0)
            Text("Spotify").tag(1)
            Text("Vox").tag(2)
            Text("Audirvana").tag(3)
            Text("Swinsian").tag(4)
        }
        .pickerStyle(.radioGroup)
        .onChange(of: preferredPlayerIndex) { newIndex in
            playerSettings.preferredPlayerIndex = newIndex
            enforcePlayerConstraints(for: newIndex)
        }
    }

    @ViewBuilder private var savingPathRow: some View {
        SettingsRow(label: "Lyrics saving path") {
            HStack {
                Picker("", selection: $savingPathPopUpIndex) {
                    Text("Default (~/Music/LyricsX)").tag(0)
                    if !customDirectoryName.isEmpty {
                        Text(customDirectoryName).tag(1)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: savingPathPopUpIndex) { idx in
                    if idx == 0 {
                        defaults[.lyricsSavingPathPopUpIndex] = 0
                    }
                }
                Button("Choose…") { chooseSavingPath() }
            }
        }
    }

    // MARK: - Helpers

    private func loadInitialState() {
        if let url = persistenceSettings.customSavingDirectory {
            customDirectoryName = url.lastPathComponent
            // Only select the custom item if the popup is already on index 1.
            // The @AppStorage binding handles restoring the saved index on its own.
        } else {
            savingPathPopUpIndex = 0
        }

        if let lan = defaults[.selectedLanguage],
           let idx = localizations.firstIndex(of: lan) {
            languagePickerIndex = idx + 2
        } else {
            languagePickerIndex = 0
        }
    }

    private func enforcePlayerConstraints(for index: Int) {
        if index < 0 {
            // Auto — disable launch-with-player
            playerSettings.launchAndQuitWithPlayer = false
            launchAndQuitWithPlayer = false
        }
        if let player = MusicPlayerName(index: index), !player.supportsBesideTrackLyrics {
            persistenceSettings.shouldLoadLyricsBesideTrack = false
            loadLyricsBesideTrack = false
        }
    }

    private func chooseSavingPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard let window = NSApp.keyWindow else {
            runSavingPanelModal(panel)
            return
        }
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url {
                commitSavingDirectory(url)
            } else {
                savingPathPopUpIndex = 0
            }
        }
    }

    private func runSavingPanelModal(_ panel: NSOpenPanel) {
        let result = panel.runModal()
        if result == .OK, let url = panel.url {
            commitSavingDirectory(url)
        } else {
            savingPathPopUpIndex = 0
        }
    }

    private func commitSavingDirectory(_ url: URL) {
        persistenceSettings.customSavingDirectory = url
        customDirectoryName = url.lastPathComponent
        defaults[.lyricsSavingPathPopUpIndex] = 1
        savingPathPopUpIndex = 1
    }

    private func applyLanguageSelection(_ index: Int) {
        if index == 0 {
            defaults.remove(.selectedLanguage)
            defaults.remove(.appleLanguages)
        } else {
            let lan = localizations[index - 2]
            defaults[.selectedLanguage] = lan
            defaults[.appleLanguages] = [lan]
        }
    }

    private func localizedLanguageName(for lan: String) -> String {
        if let idx = lan.firstIndex(of: "-") {
            let script = lan[idx...].dropFirst()
            return Locale(identifier: lan).localizedString(forScriptCode: String(script)) ?? lan
        }
        return Locale(identifier: lan).localizedString(forLanguageCode: lan) ?? lan
    }
}

// Filtered, sorted list of available localizations.
private let localizations = Bundle.main.localizations
    .filter { !$0.localizedCaseInsensitiveContains("Base") }
    .sorted()
