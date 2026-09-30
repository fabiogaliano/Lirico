//
//  AppDelegate.swift
//  Lirico - https://github.com/fabiogaliano/Lirico
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa

/// Stays running in the background while "Open and quit with music player" is on, and opens
/// Lirico whenever a supported player launches. It used to quit after opening Lirico and rely on
/// Lirico relaunching it on the way out, but a quitting app can't reliably launch another one.
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard groupDefaults.bool(forKey: launchAndQuitWithPlayer) else {
            NSApp.terminate(nil)
            return
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        // At login a player may have been reopened before this helper started.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isLaunchedAsLoginItem = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let playerRunning = NSWorkspace.shared.runningApplications.contains {
            playerBundleIdentifiers.contains($0.bundleIdentifier ?? "")
        }
        if isLaunchedAsLoginItem, playerRunning {
            openMainApp()
        }
    }

    @objc private func applicationDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              playerBundleIdentifiers.contains(app.bundleIdentifier ?? "") else { return }
        guard groupDefaults.bool(forKey: launchAndQuitWithPlayer) else {
            NSApp.terminate(nil)
            return
        }
        openMainApp()
    }

    private func openMainApp() {
        // LiricoHelper.app lives in Lirico.app/Contents/Library/LoginItems.
        var host = Bundle.main.bundleURL
        for _ in 0 ..< 4 {
            host.deleteLastPathComponent()
        }
        if let mainID = Bundle(url: host)?.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: mainID).isEmpty {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: host, configuration: configuration) { _, error in
            if let error {
                NSLog("launch Lirico failed. reason: \(error)")
            }
        }
    }
}

let playerBundleIdentifiers = [
    "com.apple.Music", "com.apple.iTunes",
    "com.spotify.client",
    "com.coppertino.Vox",
    "com.audirvana.Audirvana-Studio", "com.audirvana.Audirvana", "com.audirvana.Audirvana-Plus", "com.audirvana.Audirvana-Origin",
    "com.swinsian.Swinsian",
]

// Must match lyricsXGroupIdentifier in the main app's AppIdentifiers.swift.
#if DEBUG
let groupDefaults = UserDefaults(suiteName: "dev.fabiogaliano.Lirico.shared")!
#else
let groupDefaults = UserDefaults(suiteName: "com.fabiogaliano.Lirico.shared")!
#endif

// Preference
let launchAndQuitWithPlayer = "LaunchAndQuitWithPlayer"
