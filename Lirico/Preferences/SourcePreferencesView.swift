import SwiftUI

struct SourcePreferencesView: View {
    @State private var sourcePriorityEnabled: Bool = false
    @State private var sources: [String] = []
    @State private var selectedSource: String? = nil
    // Musixmatch token is String? — @AppStorage doesn't support optionals, so
    // it's mirrored from UserDefaults and written back through SearchSettings.
    @State private var musixmatchToken: String = ""

    private var selectedIndex: Int? {
        selectedSource.flatMap { sources.firstIndex(of: $0) }
    }

    private let searchSettings = SearchSettings()

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Prefer sources in this order", isOn: $sourcePriorityEnabled)
                    .onChange(of: sourcePriorityEnabled) { _, enabled in
                        searchSettings.sourcePriorityEnabled = enabled
                    }
                sourceList
                    .disabled(!sourcePriorityEnabled)
                moveButtons
                    .disabled(!sourcePriorityEnabled)
            } header: {
                Text("Source Priority")
            } footer: {
                SettingsFooter("Drag to reorder. Results from higher sources win over similar-quality results from lower ones.")
            }
            Section {
                LabeledContent("User token") {
                    HStack {
                        TextField("User token", text: $musixmatchToken, prompt: Text("Not set"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit { commitMusixmatchToken() }
                        Button("Apply") { commitMusixmatchToken() }
                    }
                }
            } header: {
                Text("Musixmatch")
            } footer: {
                SettingsFooter("Musixmatch is only searched once a token is set.")
            }
        }
        .onAppear { loadSettings() }
    }

    // MARK: - Sections

    private var sourceList: some View {
        // Native selection so the list is reachable by keyboard and VoiceOver, not just clicks.
        List(selection: $selectedSource) {
            ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 20, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(source)
                }
                .tag(source)
                .accessibilityValue(Text("Priority \(index + 1)"))
            }
            .onMove(perform: moveSource)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        // Sized to the rows so there is no empty well under a handful of sources.
        .frame(height: CGFloat(max(sources.count, 3)) * 24 + 6)
    }

    private var moveButtons: some View {
        HStack(spacing: 0) {
            Button(action: moveSelectedUp) {
                Image(systemName: "chevron.up").frame(width: 22, height: 18)
            }
            .disabled(selectedIndex == nil || selectedIndex == 0)
            .accessibilityLabel("Move selected source up")
            .help("Move selected source up")
            Divider().frame(height: 14)
            Button(action: moveSelectedDown) {
                Image(systemName: "chevron.down").frame(width: 22, height: 18)
            }
            .disabled(selectedIndex == nil || selectedIndex == sources.count - 1)
            .accessibilityLabel("Move selected source down")
            .help("Move selected source down")
            Spacer()
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Mutations

    private func moveSource(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        commitOrder()
    }

    private func moveSelectedUp() {
        guard let idx = selectedIndex, idx > 0 else { return }
        sources.swapAt(idx, idx - 1)
        commitOrder()
    }

    private func moveSelectedDown() {
        guard let idx = selectedIndex, idx < sources.count - 1 else { return }
        sources.swapAt(idx, idx + 1)
        commitOrder()
    }

    private func commitOrder() {
        searchSettings.sourcePriorityOrder = sources
        LyricsSelector.shared.normalize(against: availableLyricsSources(for: searchSettings), settings: searchSettings)
        sources = searchSettings.sourcePriorityOrder
    }

    // MARK: - Load

    private func loadSettings() {
        LyricsSelector.shared.normalize(against: availableLyricsSources(for: searchSettings), settings: searchSettings)
        sourcePriorityEnabled = searchSettings.sourcePriorityEnabled
        sources = searchSettings.sourcePriorityOrder
        musixmatchToken = searchSettings.musixmatchToken ?? ""
    }

    private func commitMusixmatchToken() {
        let trimmed = musixmatchToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse empty string to nil so SearchSettings treats it as "no token".
        searchSettings.musixmatchToken = trimmed.isEmpty ? nil : trimmed
        // The token adds or removes Musixmatch from the source list above.
        loadSettings()
    }
}
