import SwiftUI

struct FilterPreferencesView: View {
    @AppStorage("LyricsFilterEnabled") private var filterEnabled = true
    @AppStorage("LyricsExplicitRestorationEnabled") private var explicitRestorationEnabled = false

    @State private var keywords: [String] = []
    @State private var selectedIndex: Int? = nil

    @State private var lexicon: [String] = []
    @State private var lexiconSelectedIndex: Int? = nil

    // Rows are mostly text field, which swallows the row's tap, so focusing a field is what
    // selects it; this is also the only way keyboard and VoiceOver users can reach Remove.
    @FocusState private var focusedKeyword: Int?
    @FocusState private var focusedLexiconWord: Int?

    var body: some View {
        SettingsForm {
            filterKeywordsSection
            explicitRestorationSection
        }
        .onAppear {
            loadKeywords()
            loadLexicon()
        }
        .onChange(of: focusedKeyword) { _, index in
            if let index { selectedIndex = index }
        }
        .onChange(of: focusedLexiconWord) { _, index in
            if let index { lexiconSelectedIndex = index }
        }
    }

    // MARK: - Sections

    private var filterKeywordsSection: some View {
        Section {
            Toggle("Hide matching lines", isOn: $filterEnabled)
            editableList(count: keywords.count, row: keywordRow)
                .disabled(!filterEnabled)
            EditableListControls(
                addLabel: "Add keyword",
                removeLabel: "Remove selected keyword",
                canRemove: selectedIndex != nil,
                add: addKeyword,
                remove: removeSelected,
                reset: resetKeywords
            )
            .disabled(!filterEnabled)
        } header: {
            Text("Filter")
        } footer: {
            SettingsFooter("Hides credit lines and other noise. Start a pattern with / to use a regular expression.")
        }
    }

    private var explicitRestorationSection: some View {
        Section {
            Toggle("Restore explicit words", isOn: $explicitRestorationEnabled)
            editableList(count: lexicon.count, row: lexiconRow)
                .disabled(!explicitRestorationEnabled)
            EditableListControls(
                addLabel: "Add word",
                removeLabel: "Remove selected word",
                canRemove: lexiconSelectedIndex != nil,
                add: addLexiconWord,
                remove: removeLexiconSelected,
                reset: resetLexicon
            )
            .disabled(!explicitRestorationEnabled)
        } header: {
            Text("Censored Words")
        } footer: {
            SettingsFooter("Add each word uncensored once; censored variants like f**k are matched automatically. Only changes what's shown, not saved files or Apple Music.")
        }
    }

    private func editableList<Row: View>(count: Int, @ViewBuilder row: @escaping (Int) -> Row) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    row(index)
                    if index < count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(height: 150)
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .labelsHidden()
            .focused($focusedLexiconWord, equals: index)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(lexiconSelectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { lexiconSelectedIndex = index }
        .accessibilityAddTraits(lexiconSelectedIndex == index ? .isSelected : [])
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
            .labelsHidden()
            .font(isRegex ? .system(.body, design: .monospaced) : .body)
            .focused($focusedKeyword, equals: index)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selectedIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = index }
        .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
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
