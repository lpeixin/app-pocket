//
//  WindowBridge.swift
//  AppPocket
//
//  Gives non-view code (the global hot key, the menu bar extra) a way to show
//  and hide the launcher window.
//

import AppKit
import SwiftUI

@MainActor
final class WindowBridge {
    static let shared = WindowBridge()

    weak var window: NSWindow?

    /// Set by the root view. Lets the hot key and the menu bar recreate the
    /// window after the user has closed it.
    var reopen: (() -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Adopts SwiftUI's window exactly once.
    ///
    /// Re-applying this on every `updateNSView` is not harmless: configuring the
    /// window triggers a layout pass, which calls back into the accessor, which
    /// configures the window again. The guard breaks that cycle.
    func adopt(_ window: NSWindow?) {
        guard let window, self.window !== window else { return }
        self.window = window
        window.minSize = NSSize(width: 760, height: 480)
        window.isMovableByWindowBackground = true
        // Frame restoration is left to the `Window` scene, which already
        // persists it. Setting `frameAutosaveName` here would resize the window
        // during a layout pass.
    }

    func show() {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            reopen?()
        }
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Used by the global hot key: show when hidden, hide when already up.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Called after an app has been launched, when the user asked for the
    /// launcher to get out of the way.
    ///
    /// The window is ordered out rather than closed so the next open is instant
    /// and the scroll position survives.
    func hideAfterLaunch() {
        hide()
    }
}

/// Captures the `NSWindow` SwiftUI created for us.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard WindowBridge.shared.window == nil, let window = nsView.window else { return }
        WindowBridge.shared.adopt(window)
    }
}

extension View {
    /// Installs the window accessor in the background of a view.
    func captureLauncherWindow() -> some View {
        background(WindowAccessor())
    }
}
