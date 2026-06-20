//
//  SelectionOverlayViewTests.swift
//  GifBarTests
//
//  Unit tests for the selection overlay's keyboard-hint visibility logic
//  (Iteration 7a, SPEC §4.2 / §6). The hint is hidden on narrow panels so it
//  never clips; the threshold decision is a pure function we can test directly.
//

import XCTest
@testable import GifBar

@MainActor
final class SelectionOverlayViewTests: XCTestCase {

    func testHintHiddenBelowThreshold() {
        let width = SelectionOverlayView.hintMinimumWidth - 1
        XCTAssertFalse(SelectionOverlayView.shouldShowHint(forWidth: width))
    }

    func testHintShownAtThreshold() {
        let width = SelectionOverlayView.hintMinimumWidth
        XCTAssertTrue(SelectionOverlayView.shouldShowHint(forWidth: width))
    }

    func testHintShownAboveThreshold() {
        XCTAssertTrue(SelectionOverlayView.shouldShowHint(forWidth: 640))
    }

    func testHintHiddenAtMinimumPanelWidth() {
        // The panel can shrink to SelectionGeometry.minimumSize (80 pt wide),
        // which is well below the hint threshold.
        let width = SelectionGeometry.minimumSize.width
        XCTAssertFalse(SelectionOverlayView.shouldShowHint(forWidth: width))
    }
}
