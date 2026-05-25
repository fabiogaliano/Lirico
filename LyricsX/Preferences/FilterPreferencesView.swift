import SwiftUI

struct FilterPreferencesView: View {
    @AppStorage("LyricsFilterEnabled") private var filterEnabled = true
    @AppStorage("LyricsSmartFilterEnabled") private var smartFilterEnabled = true
    @AppStorage("LyricsExplicitRestorationEnabled") private var explicitRestorationEnabled = false

    @State private var keywords: [String] = []
    @State private var selectedIndex: Int? = nil

    @State private var lexicon: [String] = []
    @State private var lexiconSelectedIndex: Int? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filterSettingsSection
                filterKeywordsSection
                explicitRestorationSection
            }
            .padding(20)
        }
        .onAppear {
            loadKeywords()
            loadLexicon()
        }
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

    // MARK: - Explicit restoration

    private var explicitRestorationSection: some View {
        SettingsSection(title: "Restore Explicit Words") {
            Toggle("Restore explicit words", isOn: $explicitRestorationEnabled)

            Text("Add the uncensored word once — the app matches censored variants automatically "
                + "(for example f**k → fuck). Alternate lyrics found for the same song may also be "
                + "used as evidence to fill in fully masked words. This affects the displayed lyrics "
                + "only; saved files and Apple Music export are unchanged.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            lexiconList

            HStack(spacing: 8) {
                Button(action: addLexiconWord) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add word")

                Button(action: removeLexiconSelected) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.bordered)
                .disabled(lexiconSelectedIndex == nil)
                .help("Remove selected word")

                Spacer()

                Button("Reset to Defaults") {
                    resetLexicon()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var lexiconList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(lexicon.indices, id: \.self) { index in
                    lexiconRow(index: index)
                    if index < lexicon.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 220)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func lexiconRow(index: Int) -> some View {
        HStack(spacing: 6) {
            TextField("Uncensored word", text: Binding(
                get: { index < lexicon.count ? lexicon[index] : "" },
                set: { newValue in
                    guard index < lexicon.count else { return }
                    lexicon[index] = newValue
                    saveLexicon()
                }
            ))
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(lexiconSelectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { lexiconSelectedIndex = index }
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

    private func addLexiconWord() {
        lexicon.append("")
        lexiconSelectedIndex = lexicon.count - 1
        saveLexicon()
    }

    private func removeLexiconSelected() {
        guard let idx = lexiconSelectedIndex, idx < lexicon.count else { return }
        lexicon.remove(at: idx)
        if lexicon.isEmpty {
            lexiconSelectedIndex = nil
        } else {
            lexiconSelectedIndex = min(idx, lexicon.count - 1)
        }
        saveLexicon()
    }

    private func resetLexicon() {
        defaults.remove(.lyricsExplicitLexiconEntries)
        loadLexicon()
        lexiconSelectedIndex = nil
    }

    // MARK: - Persistence

    private func loadKeywords() {
        keywords = defaults[.lyricsFilterKeys]
    }

    private func saveKeywords() {
        defaults[.lyricsFilterKeys] = keywords.filter { !$0.isEmpty }
    }

    private func loadLexicon() {
        lexicon = defaults[.lyricsExplicitLexiconEntries] ?? []
    }

    private func saveLexicon() {
        defaults[.lyricsExplicitLexiconEntries] = lexicon
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
