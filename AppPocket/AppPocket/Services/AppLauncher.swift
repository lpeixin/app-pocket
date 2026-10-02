//
//  AppLauncher.swift
//  AppPocket
//
//  Thin wrapper around `NSWorkspace` for the actions the UI offers.
//

import AppKit

@MainActor
enum AppLauncher {
    /// Launches the app, bringing it to the front.
    static func open(_ app: AppInfo, completion: ((Error?) -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = true

        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error {
                NSLog("[AppPocket] Failed to launch %@: %@", app.path, String(describing: error))
            }
            completion?(error)
        }
    }

    static func reveal(_ app: AppInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    static func openContainingFolder(_ app: AppInfo) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: app.url.deletingLastPathComponent().path)
    }

    static func isRunning(_ app: AppInfo) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func quit(_ app: AppInfo) {
        guard let bundleID = app.bundleID else { return }
        for instance in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            instance.terminate()
        }
    }

    static func copyPath(_ app: AppInfo) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(app.path, forType: .string)
    }
}
