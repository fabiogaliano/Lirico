import AppKit
import LiricoFoundation
import SwiftUI

struct LyricsPreferencesView: View {
    @AppStorage(.globalLyricsOffset) private var globalLyricsOffset = 0
    @AppStorage(.preferBilingualLyrics) private var preferBilingualLyrics = false
    @AppStorage(.chineseConversionIndex) private var chineseConversionIndex = 0

    // Lyrics saving path popup index — 0 = default, 1 = custom
    @AppStorage(.lyricsSavingPathPopUpIndex) private var savingPathPopUpIndex = 0
    @AppStorage(.loadLyricsBesideTrack) private var loadLyricsBesideTrack = false

    @AppStorage(.writeToiTunesAutomatically) private var writeAutomatically = false
    @AppStorage(.writeiTunesWithTranslation) private var writeWithTranslation = false
    @AppStorage(.writeiTunesConvertToPlainLRC) private var convertToPlainLRC = false

    @AppStorage(.confirmBeforeBlockingLyrics) private var confirmBeforeBlocking = true
    @State private var blockedEntries: [BlockedEntry] = []
    @State private var selectedBlock: BlockedEntry.Kind?

    // Custom saving path display name — derived from bookmark on appear, updated
    // after the user picks a new directory via NSOpenPanel.
    @State private var customDirectoryName: String = ""

    private let persistenceSettings = PersistenceSettings()
    private let blocklist = SearchBlocklist()

    var body: some View {
        SettingsForm {
            timingSection
            displaySection
            filesSection
            appleMusicSection
            blockedSection
        }
        .onAppear(perform: loadInitialState)
        // Blocks are added from the status menu while Settings may be open. Hop to main
        // before the main-actor handler: defaults can change on any thread.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
            reloadBlockedEntries()
        }
    }

    // MARK: - Sections

    private var timingSection: some View {
        Section {
            LabeledContent("Offset for all songs") {
                HStack(spacing: 4) {
                    TextField("Offset for all songs", value: $globalLyricsOffset, formatter: NumberFormatter())
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("ms").foregroundStyle(.secondary)
                    Stepper("Offset for all songs", value: $globalLyricsOffset, step: 100)
                        .labelsHidden()
                }
            }
        } header: {
            Text("Timing")
        } footer: {
            SettingsFooter("Positive values show lyrics earlier. Each song's own offset, set from the menu bar or Sync by Ear, is added to this.")
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Toggle("Prefer bilingual lyrics", isOn: $preferBilingualLyrics)
            Picker("Chinese conversion", selection: $chineseConversionIndex) {
                Text("None").tag(0)
                Text("Simplified Chinese").tag(1)
                Text("Traditional Chinese").tag(2)
                Text("Traditional Chinese (Taiwan)").tag(3)
                Text("Traditional Chinese (Hong Kong)").tag(4)
            }
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
            Toggle("Include translation", isOn: $writeWithTranslation)
        }
    }

    private var blockedSection: some View {
        Section {
            Toggle("Ask before blocking lyrics", isOn: $confirmBeforeBlocking)
            if blockedEntries.isEmpty {
                Text("No blocked songs or albums")
                    .foregroundStyle(.secondary)
            } else {
                blockedList
                HStack(spacing: 0) {
                    Button(action: removeSelectedBlock) {
                        Image(systemName: "minus").frame(width: 22, height: 18)
                    }
                    .disabled(selectedBlock == nil)
                    .accessibilityLabel(Text("Unblock selected item"))
                    .help(Text("Unblock selected item"))
                    Spacer()
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Blocked Songs & Albums")
        } footer: {
            SettingsFooter("Lirico doesn't search lyrics for these. Unblock one to search again, or pick lyrics for the song manually.")
        }
    }

    private var blockedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(blockedEntries) { entry in
                    blockedRow(entry)
                    if entry.id != blockedEntries.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(height: CGFloat(min(blockedEntries.count, 5)) * Self.blockedRowHeight)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private static let blockedRowHeight: CGFloat = 28

    private func blockedRow(_ entry: BlockedEntry) -> some View {
        let isAlbum = if case .album = entry.kind { true } else { false }
        let isSelected = selectedBlock == entry.kind
        // A button rather than a tap gesture so VoiceOver can select the row too.
        return Button {
            selectedBlock = entry.kind
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isAlbum ? "square.stack" : "music.note")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                blockedEntryName(entry)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(isAlbum ? "Album" : "Song")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: Self.blockedRowHeight - 1)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func blockedEntryName(_ entry: BlockedEntry) -> Text {
        switch (entry.title, entry.artist) {
        case (let title?, let artist?): Text(verbatim: "\(title) — \(artist)")
        case (let title?, nil): Text(verbatim: title)
        case (nil, _): Text("Unknown track").foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func reloadBlockedEntries() {
        let entries = blocklist.entries
        guard entries != blockedEntries else { return }
        blockedEntries = entries
        if let selectedBlock, !entries.contains(where: { $0.kind == selectedBlock }) {
            self.selectedBlock = nil
        }
    }

    private func removeSelectedBlock() {
        guard let selectedBlock, let entry = blockedEntries.first(where: { $0.kind == selectedBlock }) else { return }
        blocklist.remove(entry)
        self.selectedBlock = nil
        reloadBlockedEntries()
    }

    private func loadInitialState() {
        reloadBlockedEntries()
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
