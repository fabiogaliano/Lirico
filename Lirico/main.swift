import AppKit

// Main.storyboard used to instantiate the app delegate. After removing it,
// AppKit starts with a nil delegate unless we wire one up explicitly here.
private let app = NSApplication.shared
private let appDelegate = AppDelegate()

app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
