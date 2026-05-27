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

    private var buttonTitle: String {
        switch viewModel.buttonLabel {
        case .search:      return "Search"
        case .cancel:      return "Cancel"
        case .searchAgain: return "Search Again"
        }
    }

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
                }
            }
            .width(20)

            TableColumn("Title") { result in
                HStack(spacing: 4) {
                    if result.isLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .help("Currently loaded")
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
            Spacer()
            Button("Apply") { viewModel.apply() }
                .disabled(!viewModel.canApply)
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
