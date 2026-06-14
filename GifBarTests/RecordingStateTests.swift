//
//  RecordingStateTests.swift
//  GifBarTests
//
//  Unit tests for the recording state machine (SPEC §4.3).
//

import XCTest
@testable import GifBar

final class RecordingStateTests: XCTestCase {

    private let sampleRect = CGRect(x: 10, y: 20, width: 640, height: 400)

    // MARK: - Defaults

    func testInitialStateIsIdleAt15FPS() {
        let state = RecordingState()
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.fps, .fps15)
        XCTAssertEqual(state.elapsedSecs, 0)
        XCTAssertEqual(state.selectedRect, .zero)
    }

    func testFrameRateRawValues() {
        XCTAssertEqual(RecordingState.FrameRate.fps10.rawValue, 10)
        XCTAssertEqual(RecordingState.FrameRate.fps15.rawValue, 15)
        XCTAssertEqual(RecordingState.FrameRate.fps24.rawValue, 24)
    }

    // MARK: - Legal transitions

    func testHappyPathFlow() {
        var state = RecordingState()

        XCTAssertTrue(state.apply(.selectArea))
        XCTAssertEqual(state.status, .selecting)

        XCTAssertTrue(state.apply(.startRecording(sampleRect)))
        XCTAssertEqual(state.status, .recording)
        XCTAssertEqual(state.selectedRect, sampleRect)

        XCTAssertTrue(state.apply(.stopRecording))
        XCTAssertEqual(state.status, .converting)

        XCTAssertTrue(state.apply(.conversionFinished))
        XCTAssertEqual(state.status, .done)

        XCTAssertTrue(state.apply(.reset))
        XCTAssertEqual(state.status, .idle)
    }

    func testCancelSelectionReturnsToIdle() {
        var state = RecordingState()
        state.apply(.selectArea)
        XCTAssertTrue(state.apply(.cancelSelection))
        XCTAssertEqual(state.status, .idle)
    }

    func testStartRecordingResetsElapsed() {
        var state = RecordingState()
        state.apply(.selectArea)
        state.apply(.startRecording(sampleRect))
        state.tick()
        state.tick()
        XCTAssertEqual(state.elapsedSecs, 2)

        // Restarting (via reset → select → start) clears the counter again.
        state.apply(.reset)
        state.apply(.selectArea)
        state.apply(.startRecording(sampleRect))
        XCTAssertEqual(state.elapsedSecs, 0)
    }

    // MARK: - Illegal transitions

    func testCannotStartRecordingFromIdle() {
        var state = RecordingState()
        XCTAssertFalse(state.apply(.startRecording(sampleRect)))
        XCTAssertEqual(state.status, .idle)
    }

    func testCannotStopFromIdle() {
        var state = RecordingState()
        XCTAssertFalse(state.apply(.stopRecording))
        XCTAssertEqual(state.status, .idle)
    }

    func testCannotSelectWhileRecording() {
        var state = RecordingState()
        state.apply(.selectArea)
        state.apply(.startRecording(sampleRect))
        XCTAssertFalse(state.apply(.selectArea))
        XCTAssertEqual(state.status, .recording)
    }

    func testCannotFinishConversionWhileRecording() {
        var state = RecordingState()
        state.apply(.selectArea)
        state.apply(.startRecording(sampleRect))
        XCTAssertFalse(state.apply(.conversionFinished))
        XCTAssertEqual(state.status, .recording)
    }

    // MARK: - Reset is a universal escape hatch

    func testResetFromRecordingClearsEverything() {
        var state = RecordingState()
        state.apply(.selectArea)
        state.apply(.startRecording(sampleRect))
        state.tick()

        XCTAssertTrue(state.apply(.reset))
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.elapsedSecs, 0)
        XCTAssertEqual(state.selectedRect, .zero)
    }

    func testResetPreservesFrameRate() {
        var state = RecordingState()
        state.fps = .fps24
        state.apply(.selectArea)
        state.apply(.reset)
        XCTAssertEqual(state.fps, .fps24, "fps is a preference and must survive a reset")
    }

    // MARK: - tick()

    func testTickIncrementsOnlyWhileRecording() {
        var state = RecordingState()
        state.tick()                        // idle → no-op
        XCTAssertEqual(state.elapsedSecs, 0)

        state.apply(.selectArea)
        state.tick()                        // selecting → no-op
        XCTAssertEqual(state.elapsedSecs, 0)

        state.apply(.startRecording(sampleRect))
        state.tick()
        state.tick()
        state.tick()
        XCTAssertEqual(state.elapsedSecs, 3)

        state.apply(.stopRecording)
        state.tick()                        // converting → no-op
        XCTAssertEqual(state.elapsedSecs, 3)
    }

    // MARK: - elapsedDisplay

    func testElapsedDisplayFormatting() {
        var state = RecordingState()
        XCTAssertEqual(state.elapsedDisplay, "00:00")

        state.elapsedSecs = 5
        XCTAssertEqual(state.elapsedDisplay, "00:05")

        state.elapsedSecs = 65
        XCTAssertEqual(state.elapsedDisplay, "01:05")

        state.elapsedSecs = 600
        XCTAssertEqual(state.elapsedDisplay, "10:00")
    }
}
