//
//  CaptureConfigurationTests.swift
//  GifBarTests
//
//  Unit tests for the pure capture-parameter math (SPEC §4.4).
//

import XCTest
import CoreMedia
@testable import GifBar

final class CaptureConfigurationTests: XCTestCase {

    // MARK: - sourceRect translation

    func testSourceRectIsDisplayRelative() {
        let selected = CGRect(x: 1100, y: 250, width: 640, height: 400)
        // Secondary display starting at x = 1000.
        let display = CGRect(x: 1000, y: 0, width: 1920, height: 1080)

        let config = CaptureConfiguration.make(
            selectedRect: selected, displayFrame: display, scaleFactor: 1, fps: .fps15
        )
        XCTAssertEqual(config.sourceRect, CGRect(x: 100, y: 250, width: 640, height: 400))
    }

    func testSourceRectOnPrimaryDisplayIsUnchanged() {
        let selected = CGRect(x: 50, y: 60, width: 320, height: 200)
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let config = CaptureConfiguration.make(
            selectedRect: selected, displayFrame: display, scaleFactor: 1, fps: .fps10
        )
        XCTAssertEqual(config.sourceRect, selected)
    }

    // MARK: - pixel dimensions

    func testPixelDimensionsScaleForRetina() {
        let selected = CGRect(x: 0, y: 0, width: 320, height: 200)
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let config = CaptureConfiguration.make(
            selectedRect: selected, displayFrame: display, scaleFactor: 2, fps: .fps24
        )
        XCTAssertEqual(config.pixelWidth, 640)
        XCTAssertEqual(config.pixelHeight, 400)
    }

    func testOddPixelDimensionsRoundUpToEven() {
        let selected = CGRect(x: 0, y: 0, width: 321, height: 199)
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let config = CaptureConfiguration.make(
            selectedRect: selected, displayFrame: display, scaleFactor: 1, fps: .fps15
        )
        XCTAssertEqual(config.pixelWidth, 322)
        XCTAssertEqual(config.pixelHeight, 200)
        XCTAssertTrue(config.pixelWidth.isMultiple(of: 2))
        XCTAssertTrue(config.pixelHeight.isMultiple(of: 2))
    }

    // MARK: - frame interval

    func testFrameIntervalMatchesFPS() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selected = CGRect(x: 0, y: 0, width: 100, height: 100)

        for fps in RecordingState.FrameRate.allCases {
            let config = CaptureConfiguration.make(
                selectedRect: selected, displayFrame: display, scaleFactor: 1, fps: fps
            )
            XCTAssertEqual(config.frameInterval, CMTime(value: 1, timescale: CMTimeScale(fps.rawValue)))
        }
    }

    // MARK: - bestDisplayIndex

    func testBestDisplayIndexPicksLargestOverlap() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1000, height: 1000),     // index 0
            CGRect(x: 1000, y: 0, width: 1000, height: 1000)   // index 1
        ]
        // Rect mostly on the second display.
        let rect = CGRect(x: 900, y: 100, width: 400, height: 400)
        XCTAssertEqual(CaptureConfiguration.bestDisplayIndex(for: rect, among: displays), 1)
    }

    func testBestDisplayIndexReturnsNilWhenNoOverlap() {
        let displays = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        let rect = CGRect(x: 500, y: 500, width: 50, height: 50)
        XCTAssertNil(CaptureConfiguration.bestDisplayIndex(for: rect, among: displays))
    }

    func testBestDisplayIndexReturnsNilForEmptyDisplays() {
        XCTAssertNil(CaptureConfiguration.bestDisplayIndex(for: .zero, among: []))
    }
}
