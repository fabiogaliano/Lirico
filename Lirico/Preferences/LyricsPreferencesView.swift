import AppKit
import SwiftUI

struct LyricsPreferencesView: View {
    @AppStorage(.globalLyricsOffset) private var globalLyricsOffset = 0
    @AppStorage(.preferBilingualLyrics) private var preferBilingualLyrics = false
    @AppStorage(.chineseConversionIndex) private var chineseConversionIndex = 0
    @AppStorage(.desktopLyricsEnableFurigana) private var enableFurigana = false
    @AppStorage(.desktopLyricsEnableRomajin) private var enableRomaji = false

    // Lyrics saving path popup index — 0 = default, 1 = custom
    @AppStorage(.lyricsSavingPathPopUpIndex) private var savingPathPopUpIndex = 0
    @AppStorage(.loadLyricsBesideTrack) private var loadLyricsBesideTrack = false

    @AppStorage(.writeToiTunesAutomatically) private var writeAutomatically = false
    @AppStorage(.writeiTunesWithTranslation) private var writeWithTranslation = false
    @AppStorage(.writeiTunesConvertToPlainLRC) private var convertToPlainLRC = false

    @AppStorage(.confirmBeforeBlockingLyrics) private var confirmBeforeBlocking = true

    // Custom saving path display name — derived from bookmark on appear, updated
    // after the user picks a new directory via NSOpenPanel.
    @State private var customDirectoryName: String = ""

    private let persistenceSettings = PersistenceSettings()

    var body: some View {
        SettingsForm {
            displaySection
            filesSection
            appleMusicSection
            blockedSection
        }
        .onAppear(perform: loadInitialState)
    }

    // MARK: - Sections

    private var displaySection: some View {
        Section("Display") {
            LabeledContent("Offset") {
                HStack(spacing: 4) {
                    TextField("Offset", value: $globalLyricsOffset, formatter: NumberFormatter())
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("ms").foregroundStyle(.secondary)
                    Stepper("Offset", value: $globalLyricsOffset, step: 100)
                        .labelsHidden()
                }
            }
            Toggle("Prefer bilingual lyrics", isOn: $preferBilingualLyrics)
            Picker("Chinese conversion", selection: $chineseConversionIndex) {
                Text("None").tag(0)
                Text("Simplified Chinese").tag(1)
                Text("Traditional Chinese").tag(2)
                Text("Traditional Chinese (Taiwan)").tag(3)
                Text("Traditional Chinese (Hong Kong)").tag(4)
            }
            Toggle("Show furigana for Japanese", isOn: $enableFurigana)
            Toggle("Show romaji for Japanese", isOn: $enableRomaji)
        }
    }

    private var filesSection: some View {
        Section {
            LabeledContent("Save to") {
                HStack {
                    Picker("Save to", selection: $savingPathPopUpIndex) {
                        Text("~/Music/Lirico").tag(0)
                        if !customDirectoryName.isEmpty {
                            Text(customDirectoryName).tag(1)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: savingPathPopUpIndex) { _, idx in
                        if idx == 0 {
                            defaults[.lyricsSavingPathPopUpIndex] = 0
                        }
                    }
                    Button("Choose…") { chooseSavingPath() }
                    Button {
                        NSWorkspace.shared.open(persistenceSettings.storageDirectory().url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Show in Finder")
                    .accessibilityLabel("Show in Finder")
                }
            }
            Toggle("Load lyrics beside track", isOn: $loadLyricsBesideTrack)
        } header: {
            Text("Files")
        } footer: {
            SettingsFooter("Uses an .lrc file next to the song's audio file when the player can tell Lirico where it is (Music and Vox).")
        }
    }

    private var appleMusicSection: some View {
        Section("Apple Music") {
            Toggle("Save lyrics to the song automatically", isOn: $writeAutomatically)
            Toggle("Keep timestamps (LRC)", isOn: $convertToPlainLRC)
            // LRC export is single-line per timestamp, so translations are never written into it.
            Toggle("Include translation", isOn: $writeWithTranslation)
                .disabled(convertToPlainLRC)
        }
    }

    private var blockedSection: some View {
        Section("Blocked Songs & Albums") {
            Toggle("Ask before blocking lyrics", isOn: $confirmBeforeBlocking)
        }
    }

    // MARK: - Helpers

    private func loadInitialState() {
        if let url = persistenceSettings.customSavingDirectory {
            customDirectoryName = url.lastPathComponent
        } else {
            savingPathPopUpIndex = 0
        }
    }

    private func chooseSavingPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard let window = NSApp.keyWindow else {
            if panel.runModal() == .OK, let url = panel.url {
                commitSavingDirectory(url)
            }
            return
        }
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url {
                commitSavingDirectory(url)
            }
        }
    }

    private func commitSavingDirectory(_ url: URL) {
        persistenceSettings.customSavingDirectory = url
        customDirectoryName = url.lastPathComponent
        defaults[.lyricsSavingPathPopUpIndex] = 1
        savingPathPopUpIndex = 1
    }
}
