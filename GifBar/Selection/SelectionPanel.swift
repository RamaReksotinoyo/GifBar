//
//  SelectionPanel.swift
//  GifBar
//
//  Iteration 2 — Selection overlay (SPEC §4.2).
//

import AppKit

/// A floating, borderless-looking panel whose frame defines the screen area to
/// record (selection Pattern A).
///
/// `NSPanel` is used rather than a plain `NSWindow` so the overlay can float
/// above other windows — including full-screen apps — without permanently
/// activating GifBar. The panel is allowed to become key while a selection is
/// in progress so it can receive the Esc / Return keys (SPEC §6).
final class SelectionPanel: NSPanel {
    /// Allows the panel to receive keyboard events during selection.
    override var canBecomeKey: Bool { true }

    /// The panel is a transient utility surface, never the app's main window.
    override var canBecomeMain: Bool { false }
}
