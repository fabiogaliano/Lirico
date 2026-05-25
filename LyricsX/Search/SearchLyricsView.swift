import AppKit
import SwiftUI

struct SearchLyricsView: View {
    @ObservedObject var viewModel: SearchLyricsViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchForm
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 8)

            statusLine
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            resultsAndPreview
                .padding(.horizontal, 20)

            unlikelyToggle
                .padding(.horizontal, 20)
                .padding(.top, 4)

            footer
                .padding(20)
        }
        .frame(minWidth: 720, minHeight: 480)
        // Invisible button wired to Command-Return so the shortcut applies lyrics
        // without interfering with plain Return in the text fields.
        .background(
            Button("") { if viewModel.canApply { viewModel.apply() } }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        )
        // Escape cancels the active search.
        .background(
            Button("") { viewModel.cancelSearch() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
    }

    // MARK: - Search form

    private var searchForm: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { handleReturn() }
            TextField("Artist", text: $viewModel.artist)
                .textFieldStyle(.roundedBorder)
                .onSubmit { handleReturn() }
            Button(buttonTitle) { viewModel.performButtonAction() }
                .disabled(!viewModel.canSearch && viewModel.buttonLabel == .search)
            // Subtle spinner visible while a search is running.
            ProgressView()
                .controlSize(.small)
                .opacity(viewModel.isSearching ? 1 : 0)
                .frame(width: 16)
        }
    }

    private var buttonTitle: String {
        switch viewModel.buttonLabel {
        case .search:      return "Search"
        case .cancel:      return "Cancel"
        case .searchAgain: return "Search Again"
        }
    }

    // MARK: - Status line

    /// One compact line below the search row, above the table.
    @ViewBuilder
    private var statusLine: some View {
        Text(statusCopy)
            .font(.callout)
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .animation(.default, value: statusCopy)
    }

    private var statusCopy: String {
        switch viewModel.searchStatus {
        case .idle:
            return "Enter a title, artist, or both to search"
        case .searching(let summary):
            return summary
        case .foundVisible(let count, let hidden, _):
            return hidden > 0
                ? "\(count) likely \(count == 1 ? "match" : "matches") · \(hidden) unlikely hidden"
                : "\(count) likely \(count == 1 ? "match" : "matches")"
        case .noMatches(let hidden, _):
            return hidden > 0
                ? "No likely matches found · \(hidden) unlikely hidden"
                : "No matching lyrics found"
        case .failed(let message, let count, _, _):
            return count > 0
                ? "\(message) · showing \(count) partial \(count == 1 ? "match" : "matches")"
                : "Search failed. Check your connection and try again."
        case .timedOut(let count, _, _):
            return count > 0
                ? "Search timed out · showing \(count) partial \(count == 1 ? "match" : "matches")"
                : "Search timed out. Try again."
        case .cancelled(let count, _, _):
            return count > 0
                ? "Cancelled · showing \(count) \(count == 1 ? "result" : "results")"
                : "Search cancelled"
        }
    }

    private var statusColor: Color {
        switch viewModel.searchStatus {
        case .failed, .timedOut:
            return Color(NSColor.systemOrange)
        default:
            return Color(NSColor.secondaryLabelColor)
        }
    }

    // MARK: - Results and preview

    private var resultsAndPreview: some View {
        HStack(alignment: .top, spacing: 16) {
            resultsTable
                .frame(minWidth: 360)
            previewPane
                .frame(width: 260)
        }
    }

    // MARK: - Results table

    private var resultsTable: some View {
        Table(viewModel.visibleRows, selection: $viewModel.selectionID) {
            // Mic indicator column: narrow, shows mic.fill SF Symbol for karaoke rows.
            TableColumn("") { result in
                if !result.syncIconName.isEmpty {
                    Image(systemName: result.syncIconName)
                        .foregroundStyle(Color.accentColor)
                        .help("Karaoke (word-timed) lyrics")
                }
            }
            .width(20)

            TableColumn("Title") { result in
                Text(result.title)
                    .foregroundStyle(result.isUnlikely ? Color.secondary : Color.primary)
                    .draggable(viewModel.lrcText(for: result))
            }

            TableColumn("Artist") { result in
                Text(result.artist)
                    .foregroundStyle(result.isUnlikely ? Color.secondary : Color.primary)
            }

            TableColumn("Source") { result in
                Text(result.source)
                    .foregroundStyle(result.isUnlikely ? Color.secondary : Color.primary)
            }
        }
        .onChange(of: viewModel.selectionID) { _, _ in
            viewModel.updatePreview()
        }
        // Double-click applies when Apply is enabled.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if viewModel.canApply { viewModel.apply() }
            }
        )
        .overlay {
            if viewModel.visibleRows.isEmpty {
                emptyResultsView
            }
        }
    }

    // MARK: - Empty / loading / error overlay

    @ViewBuilder
    private var emptyResultsView: some View {
        Group {
            switch viewModel.searchStatus {
            case .idle:
                Text("Enter a title, artist, or both to search")
            case .searching:
                Text("Searching…")
            case .noMatches(let hidden, _):
                if hidden > 0 {
                    Text("No likely matches found")
                } else {
                    Text("No matching lyrics found")
                }
            case .failed:
                Text("Search failed. Check your connection and try again.")
            case .timedOut:
                Text("Search timed out. Try again.")
            case .cancelled:
                Text("Search cancelled")
            case .foundVisible:
                EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    // MARK: - Unlikely toggle

    @ViewBuilder
    private var unlikelyToggle: some View {
        // Hidden when there are zero unlikely candidates; default OFF for each new search.
        if viewModel.unlikelyCount > 0 {
            Toggle(
                "Show unlikely results (\(viewModel.unlikelyCount))",
                isOn: Binding(
                    get: { viewModel.showUnlikelyResults },
                    set: { newValue in
                        viewModel.showUnlikelyResults = newValue
                        // When toggled OFF, invalidate hidden-row selection.
                        if !newValue {
                            viewModel.unlikelyToggleChanged()
                        }
                    }
                )
            )
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Preview pane

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            artworkView
            ScrollView {
                Text(viewModel.preview.isEmpty ? " " : viewModel.preview)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
    }

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
            if let image = viewModel.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("missing_artwork")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .opacity(0.6)
            }
        }
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Apply") { viewModel.apply() }
                .disabled(!viewModel.canApply)
        }
    }

    // MARK: - Keyboard helpers

    /// Return in a text field starts search when idle; starts Search Again when fields
    /// changed during an active search; does nothing when searching with unchanged fields.
    /// Plain Return never applies lyrics.
    private func handleReturn() {
        switch viewModel.buttonLabel {
        case .search:
            if viewModel.canSearch { viewModel.search() }
        case .searchAgain:
            viewModel.search()
        case .cancel:
            // Fields unchanged while searching — Return does nothing.
            break
        }
    }
}
