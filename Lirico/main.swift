import AppKit

// Main.storyboard used to instantiate the app delegate. After removing it,
// AppKit starts with a nil delegate unless we wire one up explicitly here.
// Top-level code runs on the main thread, but only Swift 6 mode treats it as
// main-actor isolated.
MainActor.assumeIsolated {
    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
    // `delegate` is weak, so the delegate has to outlive the run loop.
    withExtendedLifetime(appDelegate) {
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
