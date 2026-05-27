import AppKit

enum LyricsOffsetMenuBindings {
    static func install(stepper: NSStepper, textField: NSTextField, session: LyricsSession) {
        stepper.bind(
            .value,
            to: session,
            withKeyPath: #keyPath(LyricsSession.lyricsOffset),
            options: [.continuouslyUpdatesValue: true]
        )
        textField.bind(
            .value,
            to: session,
            withKeyPath: #keyPath(LyricsSession.lyricsOffset),
            options: [.continuouslyUpdatesValue: true]
        )
    }
}
