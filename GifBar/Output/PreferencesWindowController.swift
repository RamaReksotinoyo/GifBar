//
//  PreferencesWindowController.swift
//  GifBar
//
//  Iteration 7d — Preferences panel (SPEC §4.5 / §4.6).
//
//  Presents the Preferences window from AppKit directly. As an agent app
//  (LSUIElement), SwiftUI's `Settings` scene and `openWindow`/`openSettings`
//  from a `MenuBarExtra` open nothing visible; owning the `NSWindow` ourselves
//  (the way `SelectionOverlayController` owns its panel) is reliable.
//

import AppKit
import SwiftUI

/// Creates and shows the Preferences window on demand, reusing a single window
/// across openings. One of the few reference types allowed by SPEC §3: an
/// AppKit coordinator whose lifetime outlives the value-typed SwiftUI view.
@MainActor
final class PreferencesWindowController {
    private let preferences: PreferencesStore
    private var window: NSWindow?

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    nonisolated deinit {}

    /// Brings the app forward and shows the Preferences window, creating it on
    /// first use. Activation is required because an agent app is otherwise never
    /// foregrounded, leaving the window behind everything.
    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView(preferences: preferences))
        let window = NSWindow(contentViewController: hosting)
        window.title = "GifBar Preferences"
        window.styleMask = [.titled, .closable, .resizable]
        // Keep the window alive after closing so it can be reopened.
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
