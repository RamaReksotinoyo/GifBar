//
//  OnboardingView.swift
//  GifBar
//
//  Iteration 1 — Permission & onboarding (SPEC §5).
//

import SwiftUI

/// Explains the Screen Recording requirement and routes the user to System
/// Settings when access has been denied.
///
/// The view re-reads the authorization on appear so it can show either the
/// "grant access" call to action or, when access was previously denied, a
/// shortcut into System Settings (macOS will not prompt a second time).
struct OnboardingView: View {
    /// The permission gateway; injectable for previews and tests.
    var permission: ScreenRecordingPermission = .live
    /// Invoked once access has been granted so the host can dismiss the window.
    var onGranted: () -> Void = {}

    @State private var status: ScreenRecordingAuthorization = .notDetermined

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Screen Recording Access Needed")
                .font(.title2.weight(.semibold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: primaryAction) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 380)
        .onAppear { status = permission.authorizationStatus() }
    }

    /// Explanation text tailored to the current authorization state.
    private var message: String {
        switch status {
        case .denied:
            return "GifBar can't record the screen because access was denied. "
                + "Enable GifBar under Screen Recording in System Settings, then relaunch."
        case .granted, .notDetermined:
            return "GifBar records a selected area of your screen and exports it as a GIF. "
                + "macOS requires your permission before recording can start."
        }
    }

    /// Title for the primary button, tailored to the current state.
    private var buttonTitle: String {
        status == .denied ? "Open System Settings" : "Grant Access"
    }

    /// Requests access when undetermined, or opens System Settings when denied.
    private func primaryAction() {
        switch status {
        case .denied:
            permission.openSystemSettings()
        case .granted, .notDetermined:
            status = permission.ensureAccess()
            if status == .granted { onGranted() }
        }
    }
}

#Preview {
    OnboardingView()
}
