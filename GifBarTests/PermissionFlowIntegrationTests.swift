//
//  PermissionFlowIntegrationTests.swift
//  GifBarTests
//
//  Integration tests that exercise the permission gateway against a real
//  `UserDefaults`-backed "has requested" store, verifying that state persists
//  correctly across calls the way it would across app launches (SPEC §5).
//

import XCTest
@testable import GifBar

@MainActor
final class PermissionFlowIntegrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "GifBarTests.PermissionFlow"

    override func setUp() {
        super.setUp()
        // A throwaway suite keeps the test isolated from the real preferences.
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Builds a permission gateway backed by the throwaway defaults suite, with
    /// the live grant/request behavior replaced by a controllable stub.
    private func makePermission(
        isGranted: @escaping () -> Bool,
        requestResult: Bool
    ) -> ScreenRecordingPermission {
        let key = ScreenRecordingPermission.hasRequestedDefaultsKey
        return ScreenRecordingPermission(
            isAccessGranted: isGranted,
            requestAccess: { requestResult },
            hasRequestedBefore: { self.defaults.bool(forKey: key) },
            markRequested: { self.defaults.set(true, forKey: key) },
            openSystemSettings: {}
        )
    }

    func testDeniedFlowPersistsAcrossCalls() {
        var systemGrant = false
        let permission = makePermission(isGranted: { systemGrant }, requestResult: false)

        // Fresh state: the system can still prompt.
        XCTAssertEqual(permission.authorizationStatus(), .notDetermined)

        // User declines the prompt.
        XCTAssertEqual(permission.ensureAccess(), .denied)

        // A subsequent status check now reports denial (system won't re-prompt),
        // simulating a later app launch reading persisted state.
        XCTAssertEqual(permission.authorizationStatus(), .denied)
        _ = systemGrant // silence unused-mutation warning; kept for symmetry
    }

    func testGrantedAfterPromptStopsReportingDenied() {
        var systemGrant = false
        let permission = makePermission(isGranted: { systemGrant }, requestResult: true)

        XCTAssertEqual(permission.authorizationStatus(), .notDetermined)

        // ensureAccess prompts; emulate the system flipping to granted.
        systemGrant = true
        XCTAssertEqual(permission.ensureAccess(), .granted)

        // Once granted, status is granted regardless of the "requested" flag.
        XCTAssertEqual(permission.authorizationStatus(), .granted)
    }

    func testStatusReflectsLivePreflightOverPersistedFlag() {
        // Even if the app previously recorded a request, a later grant in
        // System Settings must win.
        defaults.set(true, forKey: ScreenRecordingPermission.hasRequestedDefaultsKey)
        let permission = makePermission(isGranted: { true }, requestResult: false)
        XCTAssertEqual(permission.authorizationStatus(), .granted)
    }
}
