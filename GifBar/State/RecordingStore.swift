//
//  RecordingStore.swift
//  GifBar
//
//  Iteration 3 — State machine (SPEC §4.3).
//

import Foundation
import Observation

/// Observable shell around the value-typed ``RecordingState``.
///
/// This is the only reference type here (SPEC §3 coordinator exception): it
/// holds the current state for SwiftUI to observe, drives the elapsed-time
/// timer while recording, and routes events through the pure state machine.
@Observable
@MainActor
final class RecordingStore {
    /// The current lifecycle state. Read-only to the outside; mutated only via
    /// ``send(_:)`` (and the internal timer).
    private(set) var state = RecordingState()

    private var timer: Timer?

    /// Applies an event to the state machine and reconciles side effects
    /// (timer, placeholder progression) with the resulting status.
    func send(_ event: RecordingState.Event) {
        guard state.apply(event) else { return }

        switch state.status {
        case .recording:
            startTimer()
        case .converting:
            stopTimer()
            // PLACEHOLDER (Iteration 4/5): there is no capture pipeline yet, so
            // nothing to convert — advance shortly so the UI doesn't get stuck.
            scheduleAfter(0.4) { $0.send(.conversionFinished) }
        case .done:
            stopTimer()
            // PLACEHOLDER (Iteration 5/6): auto-return to idle after showing
            // "Done"; later this waits for the user to dismiss the result.
            scheduleAfter(1.5) { $0.send(.reset) }
        case .idle, .selecting:
            stopTimer()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    /// Runs `work` on the main actor after `delay` seconds, if the store is
    /// still alive. Used only for the placeholder progression above.
    private func scheduleAfter(_ delay: TimeInterval, _ work: @escaping (RecordingStore) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            work(self)
        }
    }
}
