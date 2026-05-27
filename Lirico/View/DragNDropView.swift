import AppKit

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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard

        if pboard.types?.contains(.string) == true,
           let str = pboard.string(forType: .string) {
            dragDelegate?.dragFinished(content: str)
            return true
        }

        do {
            // Read file URLs via the modern .fileURL pasteboard type rather
            // than the legacy NSFilenamesPboardType property list — the
            // former is the recommended type since macOS 10.13.
            guard let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let fileURL = urls.first else {
                let errorInfo = [
                    NSLocalizedDescriptionKey: "Fail to import lyrics",
                    NSLocalizedFailureReasonErrorKey: "The file couldn’t be opened.",
                ]
                throw NSError(domain: lyricsXErrorDomain, code: 0, userInfo: errorInfo)
            }
            // `String(contentsOf:)` (the encoding-inferring overload) is
            // deprecated since macOS 14; LRC files are UTF-8 in practice.
            let str = try String(contentsOf: fileURL, encoding: .utf8)
            dragDelegate?.dragFinished(content: str)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }
}
