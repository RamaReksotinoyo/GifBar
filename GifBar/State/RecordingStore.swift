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

    /// The most recent finished output: the `.gif` once conversion succeeds, or
    /// the source `.mov` as a fallback if conversion failed. Consumed by the
    /// output handler (Iteration 6).
    private(set) var lastRecordingURL: URL?

    private let coordinator: SCStreamCoordinator
    private var timer: Timer?

    init(coordinator: SCStreamCoordinator = SCStreamCoordinator()) {
        self.coordinator = coordinator
    }

    /// Applies an event to the state machine and reconciles side effects
    /// (timer, capture lifecycle) with the resulting status.
    func send(_ event: RecordingState.Event) {
        guard state.apply(event) else { return }

        switch state.status {
        case .recording:
            startTimer()
            startCapture(rect: state.selectedRect, fps: state.fps)
        case .converting:
            stopTimer()
            finishCapture()
        case .done:
            stopTimer()
            // PLACEHOLDER (Iteration 5/6): auto-return to idle after showing
            // "Done"; later this waits for the user to dismiss the result.
            scheduleAfter(1.5) { $0.send(.reset) }
        case .idle, .selecting:
            stopTimer()
        }
    }

    // MARK: - Capture

    private func startCapture(rect: CGRect, fps: RecordingState.FrameRate) {
        Task {
            do {
                try await coordinator.start(captureRect: rect, fps: fps)
            } catch {
                print("[GifBar] failed to start capture: \(error)")
                send(.reset)
            }
        }
    }

    private func finishCapture() {
        let fps = state.fps
        Task {
            let movieURL = await coordinator.stop()
            guard let movieURL else {
                print("[GifBar] no recording to convert")
                send(.conversionFinished)
                return
            }

            do {
                let gifURL = try await MovieToGIFConverter().convert(movieURL: movieURL, fps: fps)
                lastRecordingURL = gifURL
                // SPEC §4.4: the temp .mov is an intermediate; drop it now that
                // the GIF exists.
                try? FileManager.default.removeItem(at: movieURL)
                print("[GifBar] GIF written to: \(gifURL.path)")
            } catch {
                // Keep the .mov so the recording isn't lost if encoding fails.
                print("[GifBar] GIF conversion failed: \(error)")
                lastRecordingURL = movieURL
            }
            send(.conversionFinished)
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
