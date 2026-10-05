import AppKit
import SwiftUI

struct SearchLyricsView: View {
    @ObservedObject var viewModel: SearchLyricsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .background(
            Button("") { if viewModel.canApply { viewModel.apply() } }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        )
        .background(
            Button("") { viewModel.cancelSearch() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
    }

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
            ProgressView()
                .controlSize(.small)
                .opacity(viewModel.isSearching ? 1 : 0)
                .frame(width: 16)
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch viewModel.buttonLabel {
        case .search:      return "Search"
        case .cancel:      return "Cancel"
        case .searchAgain: return "Search Again"
        }
    }

    /// Summarises the results above the table. With no rows the table's empty state says it
    /// instead; the line keeps its height so the table doesn't jump when results arrive.
    @ViewBuilder
    private var statusLine: some View {
        let hasRows = !viewModel.visibleRows.isEmpty
        Text(hasRows ? statusCopy : " ")
            .font(.callout)
            .foregroundStyle(statusColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .help(failureDetails)
            .accessibilityHidden(!hasRows)
            .animation(reduceMotion ? nil : .default, value: statusCopy)
    }

    private var statusCopy: String {
        let count = viewModel.visibleRows.count
        switch viewModel.searchStatus {
        case .idle:
            return ""
        case .searching(let summary):
            return summary
        case .finished:
            return SearchStatus.matchSummary(likely: viewModel.likelyCount, hiddenUnlikely: viewModel.hiddenUnlikelyCount)
        case .failed:
            return String(localized: "Some sources failed · \(SearchStatus.partialMatches(count))", comment: "search status; the tooltip lists the failed sources")
        case .timedOut:
            return String(localized: "Search timed out · \(SearchStatus.partialMatches(count))", comment: "search status")
        case .cancelled:
            return String(localized: "Cancelled · showing \(count) results", comment: "search status")
        }
    }

    /// The per-source errors, one per line, for the tooltip on a failed search.
    private var failureDetails: Text {
        guard case .failed(let failures) = viewModel.searchStatus else { return Text(verbatim: "") }
        return Text(verbatim: failures.joined(separator: "\n"))
    }

    private var statusColor: Color {
        switch viewModel.searchStatus {
        case .failed, .timedOut:
            return Color(NSColor.systemOrange)
        default:
            return Color(NSColor.secondaryLabelColor)
        }
    }

    private var resultsAndPreview: some View {
        HStack(alignment: .top, spacing: 16) {
            resultsTable
                .frame(minWidth: 360)
            previewPane
                .frame(width: 260)
        }
    }

    private var resultsTable: some View {
        Table(viewModel.visibleRows, selection: $viewModel.selectionID) {
            TableColumn("") { result in
                if !result.syncIconName.isEmpty {
                    Image(systemName: result.syncIconName)
                        .foregroundStyle(result.isUnlikely ? Color.secondary : Color.primary)
                        .help("Karaoke (word-timed) lyrics")
                        .accessibilityLabel("Word-synced (karaoke)")
                }
            }
            .width(20)

            TableColumn("Title") { result in
                HStack(spacing: 4) {
                    if result.isLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .help("Currently loaded")
                            .accessibilityLabel("Currently loaded")
                    }
                    Text(result.title)
                        .foregroundStyle(result.isUnlikely ? Color.secondary : Color.primary)
                }
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
        .contextMenu(forSelectionType: LyricsResult.ID.self) { _ in
            // No context menu items; this overload is used solely for its
            // double-click `primaryAction`, which Table routes through row hit-testing.
        } primaryAction: { ids in
            guard let id = ids.first else { return }
            viewModel.selectionID = id
            if viewModel.canApply { viewModel.apply() }
        }
        .overlay {
            if viewModel.visibleRows.isEmpty {
                emptyResultsView
            }
        }
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        Group {
            switch viewModel.searchStatus {
            case .idle:
                Text("Enter a title, artist, or both to search")
            case .searching(let summary):
                Text(summary)
            case .finished:
                Text(viewModel.unlikelyCount > 0 ? "No likely matches found" : "No matching lyrics found")
            case .failed:
                Text("Search failed. Check your connection and try again.")
                    .help(failureDetails)
            case .timedOut:
                Text("Search timed out. Try again.")
            case .cancelled:
                Text("Search cancelled")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var unlikelyToggle: some View {
        if viewModel.unlikelyCount > 0 {
            Toggle("Show unlikely results (\(viewModel.unlikelyCount))", isOn: $viewModel.showUnlikelyResults)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
            .overlay {
                if viewModel.selectionID == nil, !viewModel.visibleRows.isEmpty {
                    Text("Select a result to preview its lyrics")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
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

    private var footer: some View {
        HStack {
            if !viewModel.visibleRows.isEmpty, let block = viewModel.applyBlock {
                Text(applyBlockCopy(block))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Apply") { viewModel.apply() }
                .disabled(!viewModel.canApply)
        }
    }

    private func applyBlockCopy(_ block: ApplyBlock) -> LocalizedStringKey {
        switch block {
        case .nothingPlaying: "Nothing is playing. Play the song to apply lyrics to it."
        case .songChanged: "The playing song changed. Search again to apply lyrics to it."
        }
    }

    private func handleReturn() {
        switch viewModel.buttonLabel {
        case .search:
            if viewModel.canSearch { viewModel.search() }
        case .searchAgain:
            viewModel.search()
        case .cancel:
            break
        }
    }
}
