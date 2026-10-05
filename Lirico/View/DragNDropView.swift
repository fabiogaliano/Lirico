import AppKit

@MainActor
protocol DragNDropDelegate: AnyObject {
    func dragFinished(content: String)
}

final class DragNDropView: NSView {
    weak var dragDelegate: DragNDropDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string, .fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only text and lyrics files get the copy cursor, so dragging anything else over the
    /// window shows up front that it won't be imported.
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canImport(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canImport(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard

        // Files first: a file drag can also carry its name as text.
        if let fileURL = lyricsFileURL(in: pboard) {
            do {
                // `String(contentsOf:)` (the encoding-inferring overload) is
                // deprecated since macOS 14; LRC files are UTF-8 in practice.
                let str = try String(contentsOf: fileURL, encoding: .utf8)
                dragDelegate?.dragFinished(content: str)
                return true
            } catch {
                let failure = NSError(domain: lyricsXErrorDomain, code: 0, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("Couldn't Import Lyrics", comment: "import error title"),
                    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(
                        "The file couldn't be read. Lirico reads lyrics files saved as UTF-8 text.",
                        comment: "import error"
                    ),
                    NSUnderlyingErrorKey: error,
                ])
                showImportError(failure)
                return false
            }
        }

        if let str = pboard.string(forType: .string) {
            dragDelegate?.dragFinished(content: str)
            return true
        }
        return false
    }

    private func canImport(_ pboard: NSPasteboard) -> Bool {
        lyricsFileURL(in: pboard) != nil || pboard.types?.contains(.string) == true
    }

    private func lyricsFileURL(in pboard: NSPasteboard) -> URL? {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { Self.lyricsFileExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static let lyricsFileExtensions: Set<String> = ["lrc", "lrcx", "txt"]

    /// A sheet on the lyrics window rather than an app-wide modal alert.
    private func showImportError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
