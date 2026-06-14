//
//  ScreenRecordingPermission.swift
//  GifBar
//
//  Iteration 1 — Permission & onboarding (SPEC §5).
//

import AppKit
import CoreGraphics
import Foundation

/// The macOS Screen Recording authorization state, as far as the app can
/// determine it.
///
/// macOS does not expose a tri-state API for Screen Recording:
/// `CGPreflightScreenCaptureAccess()` only reports whether access is *currently*
/// granted. We therefore distinguish ``denied`` from ``notDetermined`` by
/// remembering whether the app has already asked the system at least once.
enum ScreenRecordingAuthorization: Equatable {
    /// The user has granted Screen Recording access.
    case granted
    /// The user has explicitly denied access; the system will not prompt again.
    case denied
    /// Access has never been requested, so the system can still show a prompt.
    case notDetermined
}

/// A small, value-typed gateway around the system Screen Recording permission.
///
/// Every side-effecting system call is injected as a closure, so the decision
/// logic can be unit tested without touching the real TCC database or showing
/// a system dialog. Production code uses ``ScreenRecordingPermission/live``.
struct ScreenRecordingPermission {
    /// Returns `true` when Screen Recording access is currently granted.
    var isAccessGranted: () -> Bool
    /// Prompts the user for access (only effective while access is still
    /// undetermined) and returns the resulting grant state.
    var requestAccess: () -> Bool
    /// Returns `true` once the app has asked the system at least once.
    var hasRequestedBefore: () -> Bool
    /// Persists that the app has now asked the system at least once.
    var markRequested: () -> Void
    /// Opens the Screen Recording pane in System Settings.
    var openSystemSettings: () -> Void

    /// Resolves the current authorization *without* prompting the user.
    func authorizationStatus() -> ScreenRecordingAuthorization {
        if isAccessGranted() { return .granted }
        return hasRequestedBefore() ? .denied : .notDetermined
    }

    /// Ensures access, prompting the system dialog the first time.
    ///
    /// - Returns: ``ScreenRecordingAuthorization/granted`` when access is (now)
    ///   available, otherwise ``ScreenRecordingAuthorization/denied``. After this
    ///   call the system will never prompt again, so a `.denied` result should
    ///   route the user to System Settings.
    func ensureAccess() -> ScreenRecordingAuthorization {
        if isAccessGranted() { return .granted }
        markRequested()
        return requestAccess() ? .granted : .denied
    }
}

extension ScreenRecordingPermission {
    /// `UserDefaults` key used to remember, across launches, that the system has
    /// been asked for Screen Recording access at least once.
    static let hasRequestedDefaultsKey = "screenRecording.hasRequested"

    /// URL that opens the Screen Recording pane in System Settings.
    static let systemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// The production instance, wired to CoreGraphics and `NSWorkspace`.
    static var live: ScreenRecordingPermission {
        let defaults = UserDefaults.standard
        return ScreenRecordingPermission(
            isAccessGranted: { CGPreflightScreenCaptureAccess() },
            requestAccess: { CGRequestScreenCaptureAccess() },
            hasRequestedBefore: { defaults.bool(forKey: hasRequestedDefaultsKey) },
            markRequested: { defaults.set(true, forKey: hasRequestedDefaultsKey) },
            openSystemSettings: {
                if let url = URL(string: systemSettingsURLString) {
                    NSWorkspace.shared.open(url)
                }
            }
        )
    }
}
