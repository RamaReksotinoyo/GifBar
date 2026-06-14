//
//  SelectionGeometryTests.swift
//  GifBarTests
//
//  Unit tests for the selection-overlay coordinate math (SPEC §4.2).
//

import XCTest
@testable import GifBar

final class SelectionGeometryTests: XCTestCase {

    // MARK: - captureRect(fromAppKitFrame:primaryScreenHeight:)

    func testCaptureRectFlipsYAxis() {
        let appKit = CGRect(x: 100, y: 200, width: 300, height: 150)
        let capture = SelectionGeometry.captureRect(
            fromAppKitFrame: appKit, primaryScreenHeight: 1000
        )
        // top edge in capture coords = 1000 - 200 - 150 = 650
        XCTAssertEqual(capture, CGRect(x: 100, y: 650, width: 300, height: 150))
    }

    func testCaptureRectAtBottomOfPrimaryScreen() {
        let appKit = CGRect(x: 0, y: 0, width: 400, height: 300)
        let capture = SelectionGeometry.captureRect(
            fromAppKitFrame: appKit, primaryScreenHeight: 1000
        )
        // A rect sitting on the bottom edge maps to (height - rectHeight) at top.
        XCTAssertEqual(capture, CGRect(x: 0, y: 700, width: 400, height: 300))
    }

    func testCaptureRectAbovePrimaryYieldsNegativeY() {
        // A display stacked above the primary has AppKit Y greater than the
        // primary height; its capture origin must become negative.
        let appKit = CGRect(x: 0, y: 1080, width: 200, height: 200)
        let capture = SelectionGeometry.captureRect(
            fromAppKitFrame: appKit, primaryScreenHeight: 1000
        )
        XCTAssertEqual(capture.origin.y, 1000 - 1080 - 200) // -280
    }

    func testCaptureRectPreservesSizeAndX() {
        let appKit = CGRect(x: 42, y: 17, width: 321, height: 123)
        let capture = SelectionGeometry.captureRect(
            fromAppKitFrame: appKit, primaryScreenHeight: 900
        )
        XCTAssertEqual(capture.origin.x, 42)
        XCTAssertEqual(capture.size, CGSize(width: 321, height: 123))
    }

    // MARK: - enforcingMinimumSize(_:)

    func testEnforcingMinimumSizeGrowsTooSmallRect() {
        let small = CGRect(x: 10, y: 20, width: 10, height: 10)
        let result = SelectionGeometry.enforcingMinimumSize(small)
        XCTAssertEqual(result.origin, CGPoint(x: 10, y: 20))
        XCTAssertEqual(result.size, SelectionGeometry.minimumSize)
    }

    func testEnforcingMinimumSizeLeavesLargeRectUnchanged() {
        let large = CGRect(x: 0, y: 0, width: 500, height: 400)
        XCTAssertEqual(SelectionGeometry.enforcingMinimumSize(large), large)
    }

    func testEnforcingMinimumSizeGrowsOnlyDeficientDimension() {
        let wideButShort = CGRect(x: 0, y: 0, width: 500, height: 10)
        let result = SelectionGeometry.enforcingMinimumSize(wideButShort)
        XCTAssertEqual(result.width, 500)
        XCTAssertEqual(result.height, SelectionGeometry.minimumSize.height)
    }

    // MARK: - dimensionLabel(for:)

    func testDimensionLabelFormatsWholePoints() {
        XCTAssertEqual(SelectionGeometry.dimensionLabel(for: CGSize(width: 640, height: 400)), "640 × 400")
    }

    func testDimensionLabelRoundsFractionalPoints() {
        XCTAssertEqual(SelectionGeometry.dimensionLabel(for: CGSize(width: 639.6, height: 400.2)), "640 × 400")
    }
}
