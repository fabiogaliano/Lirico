import SwiftUI

struct SourcePreferencesView: View {
    @State private var sourcePriorityEnabled: Bool = false
    @State private var sources: [String] = []
    @State private var selectedIndex: Int? = nil

    private let searchSettings = SearchSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourcePrioritySection
            }
            .padding(20)
        }
        .onAppear { loadSettings() }
    }

    // MARK: - Sections

    private var sourcePrioritySection: some View {
        SettingsSection(title: "Source Priority") {
            Toggle("Enable source priority", isOn: $sourcePriorityEnabled)
                .onChange(of: sourcePriorityEnabled) { _, enabled in
                    searchSettings.sourcePriorityEnabled = enabled
                }

            Text("Drag rows to reorder. When enabled, higher-priority sources are preferred over lower-quality results from lower-priority sources.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            sourceList
                .opacity(sourcePriorityEnabled ? 1.0 : 0.5)
                .disabled(!sourcePriorityEnabled)

            moveButtons
                .opacity(sourcePriorityEnabled ? 1.0 : 0.5)
                .disabled(!sourcePriorityEnabled)
        }
    }

    private var sourceList: some View {
        List {
            ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .foregroundColor(.secondary)
                        .frame(width: 24, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                    Text(source)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedIndex = index }
                .background(selectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .onMove(perform: moveSource)
        }
        .listStyle(.plain)
        .frame(minHeight: 150, maxHeight: 230)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var moveButtons: some View {
        HStack(spacing: 8) {
            Button(action: moveSelectedUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIndex == nil || selectedIndex == 0)
            .help("Move selected source up")

            Button(action: moveSelectedDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.bordered)
            .disabled(selectedIndex == nil || selectedIndex == sources.count - 1)
            .help("Move selected source down")

            Spacer()
        }
    }

    // MARK: - Mutations

    private func moveSource(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        // Recompute selectedIndex to track the moved row.
        if let old = selectedIndex, let moved = offsets.first {
            let dest = destination > moved ? destination - 1 : destination
            if old == moved {
                selectedIndex = dest
            } else if moved < old && dest >= old {
                selectedIndex = old - 1
            } else if moved > old && dest <= old {
                selectedIndex = old + 1
            }
        }
        commitOrder()
    }

    private func moveSelectedUp() {
        guard let idx = selectedIndex, idx > 0 else { return }
        sources.swapAt(idx, idx - 1)
        selectedIndex = idx - 1
        commitOrder()
    }

    private func moveSelectedDown() {
        guard let idx = selectedIndex, idx < sources.count - 1 else { return }
        sources.swapAt(idx, idx + 1)
        selectedIndex = idx + 1
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
    }
}
