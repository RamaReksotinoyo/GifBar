//
//  RecordingState.swift
//  GifBar
//
//  Iteration 3 — State machine (SPEC §4.3).
//
//  A flat, value-typed state machine for the recording lifecycle. All
//  transition logic lives here as pure functions so it can be unit tested
//  without any AppKit / timer involvement.
//

import CoreGraphics
import Foundation

/// The full recording lifecycle state. A `struct` (value semantics, `Sendable`)
/// as required by SPEC §3.2; the observable shell lives in `RecordingStore`.
struct RecordingState: Equatable, Sendable {
    /// Where the app currently sits in the recording lifecycle.
    enum Status: UInt8, Equatable, Sendable {
        case idle, selecting, recording, converting, done
    }

    /// Capture frame rate. 60 FPS is intentionally absent (SPEC §4.5).
    enum FrameRate: UInt8, Equatable, Sendable, CaseIterable {
        case fps10 = 10
        case fps15 = 15
        case fps24 = 24
    }

    /// Events that drive transitions. Carrying the rect on `startRecording`
    /// keeps the state self-contained.
    enum Event: Equatable, Sendable {
        case selectArea
        case cancelSelection
        case startRecording(CGRect)
        case stopRecording
        case conversionFinished
        case reset
    }

    var status: Status = .idle
    var elapsedSecs: UInt32 = 0
    var selectedRect: CGRect = .zero
    var fps: FrameRate = .fps15

    // MARK: - Transitions

    /// Applies an event, returning `true` if it was legal in the current state.
    ///
    /// Illegal transitions are rejected without mutating the state, which is
    /// the whole point of modelling this as a state machine: e.g. you cannot
    /// jump straight from `.idle` to `.recording` without selecting first.
    /// `.reset` is a deliberate universal escape hatch back to `.idle`.
    @discardableResult
    mutating func apply(_ event: Event) -> Bool {
        switch (status, event) {
        case (.idle, .selectArea):
            status = .selecting
        case (.selecting, .startRecording(let rect)):
            selectedRect = rect
            elapsedSecs = 0
            status = .recording
        case (.selecting, .cancelSelection):
            resetState()
        case (.recording, .stopRecording):
            status = .converting
        case (.converting, .conversionFinished):
            status = .done
        case (_, .reset):
            resetState()
        default:
            return false
        }
        return true
    }

    /// Advances the elapsed counter by one second, but only while recording.
    mutating func tick() {
        guard status == .recording else { return }
        elapsedSecs &+= 1
    }

    // MARK: - Derived values

    /// Elapsed time formatted as `mm:ss` for display in the menu.
    var elapsedDisplay: String {
        let total = Int(elapsedSecs)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Private

    /// Returns to idle and clears per-recording fields. The chosen `fps`
    /// (a user preference) is intentionally preserved.
    private mutating func resetState() {
        status = .idle
        elapsedSecs = 0
        selectedRect = .zero
    }
}
