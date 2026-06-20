//
//  GifBarApp.swift
//  GifBar
//
//  Created by Anugrah Tri Ramadhan on 14/06/26.
//

import SwiftUI
import AppKit

@main
struct GifBarApp: App {
    /// Identifier of the onboarding `Window` scene, shared between the menu bar
    /// content (which opens it) and the view (which dismisses it).
    static let onboardingWindowID = "onboarding"

    /// Output preferences (save folder, reveal-in-Finder), shared by the store
    /// that writes GIFs and the menu that lets the user pick a folder.
    private let preferences = PreferencesStore()

    /// Holds the recording lifecycle state, observed by the menu.
    private let store: RecordingStore

    /// Owns the selection panel's lifetime; created once so it survives the
    /// repeated re-evaluation of the menu bar content.
    private let overlayController = SelectionOverlayController()

    /// Owns the Preferences window; created once so it survives menu re-renders.
    private let preferencesWindow: PreferencesWindowController

    init() {
        store = RecordingStore(preferences: preferences)
        preferencesWindow = PreferencesWindowController(preferences: preferences)

        // The selection panel reports its outcome straight into the state
        // machine: a committed rect starts recording, Esc cancels.
        overlayController.onCommit = { [store] rect in
            store.send(.startRecording(rect))
        }
        overlayController.onCancel = { [store] in
            store.send(.cancelSelection)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                store: store,
                overlayController: overlayController,
                preferences: preferences,
                preferencesWindow: preferencesWindow
            )
        } label: {
            MenuBarLabel(store: store)
        }

        Window("Welcome to GifBar", id: Self.onboardingWindowID) {
            OnboardingView(onGranted: dismissOnboarding)
        }
        .windowResizability(.contentSize)
    }

    /// Closes the onboarding window once Screen Recording access is granted.
    @MainActor private func dismissOnboarding() {
        for window in NSApp.windows where window.identifier?.rawValue == Self.onboardingWindowID {
            window.close()
        }
    }
}

/// The menu bar status-item label. Shows a plain record glyph when idle and the
/// live elapsed time beside a stop glyph while recording, so progress is visible
/// without opening the menu (SPEC §4.3).
struct MenuBarLabel: View {
    let store: RecordingStore

    var body: some View {
        switch store.state.status {
        case .recording:
            // In the menu bar a `Label` collapses to icon-only, hiding the time.
            // Interpolating the glyph into a `Text` keeps the elapsed time
            // visible beside it.
            Text("\(Image(systemName: "stop.circle.fill")) \(store.state.elapsedDisplay)")
        case .converting:
            Image(systemName: "circle.dotted")
        case .idle, .selecting, .done:
            Image(systemName: "record.circle")
        }
    }
}

/// Contents of the menu bar dropdown. Kept as its own `View` so it can read the
/// `openWindow` environment action, which is unavailable directly in `App`.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    /// Recording lifecycle state; the menu re-renders as its status changes.
    let store: RecordingStore

    /// Coordinator that presents the floating selection panel.
    let overlayController: SelectionOverlayController

    /// Output preferences, including the chosen save folder.
    let preferences: PreferencesStore

    /// Opens the Preferences window (managed in AppKit, not via `openWindow`).
    let preferencesWindow: PreferencesWindowController

    /// The permission gateway; injectable for previews and tests.
    var permission: ScreenRecordingPermission = .live

    var body: some View {
        statusItems

        Divider()

        Toggle("Copy to Clipboard", isOn: Binding(
            get: { preferences.preferences.copyToClipboard },
            set: { preferences.setCopyToClipboard($0) }
        ))

        Button("Preferences…") {
            preferencesWindow.show()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit GifBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Menu items that depend on where we are in the recording lifecycle.
    @ViewBuilder
    private var statusItems: some View {
        switch store.state.status {
        case .idle:
            Button("Record Area") { recordArea() }

        case .selecting:
            Button("Cancel Selection") {
                overlayController.dismiss()
                store.send(.cancelSelection)
            }

        case .recording:
            Text("Recording \(store.state.elapsedDisplay)")
            Button("Stop Recording") { store.send(.stopRecording) }

        case .converting:
            Text("Converting…")

        case .done:
            Text("Done")
        }
    }

    /// Lazily ensures Screen Recording access on first use (SPEC §5, option B).
    ///
    /// When access is granted the selection flow begins; otherwise the
    /// onboarding window is brought to the front to guide the user.
    private func recordArea() {
        guard permission.ensureAccess() == .granted else {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: GifBarApp.onboardingWindowID)
            return
        }
        store.send(.selectArea)
        overlayController.present()
    }
}
