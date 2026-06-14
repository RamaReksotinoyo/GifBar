//
//  ScreenRecordingPermissionTests.swift
//  GifBarTests
//
//  Unit tests for the Screen Recording permission decision logic (SPEC §5).
//

import XCTest
@testable import GifBar

@MainActor
final class ScreenRecordingPermissionTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a permission gateway with overridable behavior. Counters let tests
    /// assert which side effects were triggered.
    private func makePermission(
        granted: Bool = false,
        requestResult: Bool = false,
        requestedBefore: Bool = false,
        onMarkRequested: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) -> ScreenRecordingPermission {
        ScreenRecordingPermission(
            isAccessGranted: { granted },
            requestAccess: { requestResult },
            hasRequestedBefore: { requestedBefore },
            markRequested: onMarkRequested,
            openSystemSettings: onOpenSettings
        )
    }

    // MARK: - authorizationStatus()

    func testStatusIsGrantedWhenAccessGranted() {
        let permission = makePermission(granted: true, requestedBefore: false)
        XCTAssertEqual(permission.authorizationStatus(), .granted)
    }

    func testStatusIsNotDeterminedWhenNeverRequested() {
        let permission = makePermission(granted: false, requestedBefore: false)
        XCTAssertEqual(permission.authorizationStatus(), .notDetermined)
    }

    func testStatusIsDeniedWhenRequestedButNotGranted() {
        let permission = makePermission(granted: false, requestedBefore: true)
        XCTAssertEqual(permission.authorizationStatus(), .denied)
    }

    // MARK: - ensureAccess()

    func testEnsureAccessReturnsGrantedWithoutRequestingWhenAlreadyGranted() {
        var marked = false
        var requested = false
        let permission = ScreenRecordingPermission(
            isAccessGranted: { true },
            requestAccess: { requested = true; return true },
            hasRequestedBefore: { false },
            markRequested: { marked = true },
            openSystemSettings: {}
        )

        XCTAssertEqual(permission.ensureAccess(), .granted)
        XCTAssertFalse(marked, "Should not mark requested when access is already granted")
        XCTAssertFalse(requested, "Should not prompt when access is already granted")
    }

    func testEnsureAccessPromptsAndReturnsGrantedWhenUserAllows() {
        var marked = false
        let permission = ScreenRecordingPermission(
            isAccessGranted: { false },
            requestAccess: { true },
            hasRequestedBefore: { false },
            markRequested: { marked = true },
            openSystemSettings: {}
        )

        XCTAssertEqual(permission.ensureAccess(), .granted)
        XCTAssertTrue(marked, "Should record that the system was asked")
    }

    func testEnsureAccessPromptsAndReturnsDeniedWhenUserRefuses() {
        var marked = false
        let permission = ScreenRecordingPermission(
            isAccessGranted: { false },
            requestAccess: { false },
            hasRequestedBefore: { false },
            markRequested: { marked = true },
            openSystemSettings: {}
        )

        XCTAssertEqual(permission.ensureAccess(), .denied)
        XCTAssertTrue(marked, "Should record that the system was asked even on denial")
    }

    // MARK: - openSystemSettings()

    func testOpenSystemSettingsForwardsToClosure() {
        var opened = false
        let permission = makePermission(onOpenSettings: { opened = true })
        permission.openSystemSettings()
        XCTAssertTrue(opened)
    }

    func testSystemSettingsURLIsValid() {
        XCTAssertNotNil(URL(string: ScreenRecordingPermission.systemSettingsURLString))
    }
}
