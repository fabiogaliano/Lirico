import AppKit
import SwiftUI

struct SearchLyricsView: View {
    @ObservedObject var viewModel: SearchLyricsViewModel

    var body: some View {
        VStack(spacing: 16) {
            searchForm
            resultsAndPreview
            footer
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: - Sections

    private var searchForm: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
            TextField("Artist", text: $viewModel.artist)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runSearch() }
            Button("Search") { runSearch() }
                .disabled(!viewModel.canSearch || viewModel.isSearching)
            ProgressView()
                .controlSize(.small)
                .opacity(viewModel.isSearching ? 1 : 0)
                .frame(width: 16)
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
        Table(viewModel.results, selection: $viewModel.selectionID) {
            TableColumn("Title") { result in
                Text(result.title)
                    .draggable(viewModel.lrcText(for: result))
            }
            TableColumn("Artist", value: \.artist)
            TableColumn("Source", value: \.source)
        }
        .onChange(of: viewModel.selectionID) { _, _ in
            viewModel.updatePreview()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if viewModel.canApply { viewModel.apply() }
            }
        )
        .overlay {
            if viewModel.results.isEmpty {
                emptyResultsView
            }
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

    @ViewBuilder
    private var emptyResultsView: some View {
        Group {
            if !viewModel.hasTrack {
                Text("No track is playing")
            } else if viewModel.isSearching {
                Text("Searching…")
            } else if viewModel.canSearch {
                Text("No results yet")
            } else {
                Text("Enter a song title to search")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Apply") { viewModel.apply() }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canApply)
        }
    }

    private func runSearch() {
        guard viewModel.canSearch else { return }
        viewModel.search()
    }
}
