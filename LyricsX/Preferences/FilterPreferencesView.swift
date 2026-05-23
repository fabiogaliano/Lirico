import SwiftUI

struct FilterPreferencesView: View {
    @AppStorage("LyricsFilterEnabled") private var filterEnabled = true
    @AppStorage("LyricsSmartFilterEnabled") private var smartFilterEnabled = true

    @State private var keywords: [String] = []
    @State private var selectedIndex: Int? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterSettingsSection
                filterKeywordsSection
            }
            .padding(20)
        }
        .onAppear { loadKeywords() }
    }

    // MARK: - Sections

    private var filterSettingsSection: some View {
        SettingsSection(title: "Filter Settings") {
            Toggle("Enable lyrics filter", isOn: $filterEnabled)
            Toggle("Smart filter", isOn: $smartFilterEnabled)
        }
    }

    private var filterKeywordsSection: some View {
        SettingsSection(title: "Filter Keywords") {
            Text("Lines matching these keywords or patterns will be hidden. Patterns beginning with / are treated as regular expressions.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            keywordList

            HStack(spacing: 8) {
                Button(action: addKeyword) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add keyword")

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(selectedIndex == nil)
                .help("Remove selected keyword")

                Spacer()

                Button("Reset to Defaults") {
                    resetKeywords()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var keywordList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(keywords.indices, id: \.self) { index in
                    keywordRow(index: index)
                    if index < keywords.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(minHeight: 160, maxHeight: 260)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func keywordRow(index: Int) -> some View {
        let isRegex = keywords[index].hasPrefix("/")
        HStack(spacing: 6) {
            if isRegex {
                Text(".*")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 22)
            } else {
                Spacer()
                    .frame(width: 22)
            }
            TextField("Keyword or /pattern/", text: Binding(
                get: { index < keywords.count ? keywords[index] : "" },
                set: { newValue in
                    guard index < keywords.count else { return }
                    keywords[index] = newValue
                    saveKeywords()
                }
            ))
            .textFieldStyle(.plain)
            .font(isRegex ? .system(.body, design: .monospaced) : .body)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = index }
    }

    // MARK: - Mutations

    private func addKeyword() {
        keywords.append("")
        selectedIndex = keywords.count - 1
        saveKeywords()
    }

    private func removeSelected() {
        guard let idx = selectedIndex, idx < keywords.count else { return }
        keywords.remove(at: idx)
        if keywords.isEmpty {
            selectedIndex = nil
        } else {
            selectedIndex = min(idx, keywords.count - 1)
        }
        saveKeywords()
    }

    private func resetKeywords() {
        defaults.remove(.lyricsFilterKeys)
        loadKeywords()
        selectedIndex = nil
    }

    // MARK: - Persistence

    private func loadKeywords() {
        keywords = defaults[.lyricsFilterKeys]
    }

    private func saveKeywords() {
        defaults[.lyricsFilterKeys] = keywords.filter { !$0.isEmpty }
    }
}
