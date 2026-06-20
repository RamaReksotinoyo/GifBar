//
//  PreferencesTests.swift
//  GifBarTests
//
//  Unit tests for PreferencesStore persistence. Uses an isolated UserDefaults
//  suite so the real app defaults are untouched (SPEC §4.6).
//
//  Note: the security-scoped save-folder bookmark is created from an NSOpenPanel
//  URL at runtime (the sandbox grants access via powerbox), which a unit test
//  cannot synthesize. That path is verified at runtime, not here; these tests
//  cover the surrounding persistence logic.
//

import XCTest
@testable import GifBar

@MainActor
final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "gifbar-prefs-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToRevealEnabledAndNoFolder() {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertTrue(store.preferences.revealInFinder)
        XCTAssertNil(store.preferences.folderBookmark)
        XCTAssertNil(store.resolveSaveFolder(), "no bookmark set yet")
    }

    func testRevealInFinderPersistsAcrossStores() {
        let store = PreferencesStore(defaults: defaults)
        store.setRevealInFinder(false)

        // A fresh store reading the same suite should see the change.
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertFalse(reloaded.preferences.revealInFinder)
    }

    func testRevealInFinderRoundTripsTrue() {
        let store = PreferencesStore(defaults: defaults)
        store.setRevealInFinder(false)
        store.setRevealInFinder(true)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertTrue(reloaded.preferences.revealInFinder)
    }

    func testCopyToClipboardDefaultsToFalse() {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertFalse(store.preferences.copyToClipboard)
    }

    func testCopyToClipboardPersistsAcrossStores() {
        let store = PreferencesStore(defaults: defaults)
        store.setCopyToClipboard(true)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertTrue(reloaded.preferences.copyToClipboard)
    }

    func testFPSDefaultsTo15() {
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences.fps, .fps15)
    }

    func testFPSPersistsAcrossStores() {
        let store = PreferencesStore(defaults: defaults)
        store.setFPS(.fps24)

        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.fps, .fps24)
    }
}
