//
//  AppPocketUITests.swift
//  AppPocketUITests
//
//  A launch smoke test for the refactored launcher.
//
//  Scope is deliberately tiny. Everything that can be checked without a window
//  server — category CRUD, membership, persistence, filtering, ordering,
//  scanning — is covered by `AppPocketTests`, which run headlessly. What only
//  XCUITest can prove is that the app launches and puts a real window with real
//  controls on screen, so that is all this file does.
//
//  The 448 lines of `UITests.swift` that used to sit next to this file drove a
//  window called "PocketLauncher", from an earlier name for this app. Every one
//  of those tests addressed a window that no longer exists, so they were
//  deleted rather than left to fail.
//

import XCTest

final class AppPocketUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The launcher window comes up, and it has interactive content.
    ///
    /// Nothing here asserts on text: every label is localized, so a
    /// text-based assertion would fail on a non-English system.
    @MainActor
    func testLauncherWindowAppearsWithControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30),
            "The launcher window never appeared."
        )

        XCTAssertGreaterThan(
            app.buttons.count,
            0,
            "The launcher window has no buttons: the sidebar or the grid failed to build."
        )
    }

    /// Closing the launcher window must not quit the app — the menu bar extra
    /// and the global hot key have to survive so the user can bring it back.
    /// `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns
    /// `false` for exactly this reason.
    @MainActor
    func testAppStaysAliveWhenTheLauncherWindowIsClosed() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "The launcher window never appeared.")

        window.buttons[XCUIIdentifierCloseWindow].click()

        XCTAssertNotEqual(
            app.state,
            .notRunning,
            "The app terminated when its only window was closed."
        )
    }
}
