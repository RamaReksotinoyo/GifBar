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

    var body: some Scene {
        MenuBarExtra("GifBar", systemImage: "record.circle") {
            MenuBarContent()
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

/// Contents of the menu bar dropdown. Kept as its own `View` so it can read the
/// `openWindow` environment action, which is unavailable directly in `App`.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    /// The permission gateway; injectable for previews and tests.
    var permission: ScreenRecordingPermission = .live

    var body: some View {
        Button("Record Area") { recordArea() }

        Button("Preferences…") {
            // TODO: Iteration 7 — open the Preferences panel.
        }

        Divider()

        Button("Quit GifBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Lazily ensures Screen Recording access on first use (SPEC §5, option B).
    ///
    /// When access is granted the recording flow continues; otherwise the
    /// onboarding window is brought to the front to guide the user.
    private func recordArea() {
        if permission.ensureAccess() == .granted {
            // TODO: Iteration 2 — present the selection overlay.
        } else {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: GifBarApp.onboardingWindowID)
        }
    }
}
