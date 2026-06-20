//
//  RecordingStore.swift
//  GifBar
//
//  Iteration 3 — State machine (SPEC §4.3).
//

import AppKit
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
    private let preferences: PreferencesStore
    private var timer: Timer?

    init(coordinator: SCStreamCoordinator = SCStreamCoordinator(),
         preferences: PreferencesStore? = nil) {
        self.coordinator = coordinator
        self.preferences = preferences ?? PreferencesStore()
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
                // SPEC §4.4: the temp .mov is an intermediate; drop it now that
                // the GIF exists.
                try? FileManager.default.removeItem(at: movieURL)
                lastRecordingURL = deliverOutput(gifURL: gifURL)
            } catch {
                // Keep the .mov so the recording isn't lost if encoding fails.
                print("[GifBar] GIF conversion failed: \(error)")
                lastRecordingURL = movieURL
            }
            send(.conversionFinished)
        }
    }

    /// Moves the finished GIF into the user's chosen save folder (SPEC §4.6) and
    /// optionally reveals it in Finder. Falls back to leaving the GIF in temp if
    /// no folder is configured or saving fails, so the recording is never lost.
    ///
    /// - Returns: The final on-disk URL of the GIF.
    private func deliverOutput(gifURL: URL) -> URL {
        guard let (folder, _) = preferences.resolveSaveFolder() else {
            print("[GifBar] no save folder set; GIF left at \(gifURL.path)")
            return gifURL
        }

        // Sandbox: a bookmark-resolved URL must be unlocked for the duration of
        // the file operation.
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        do {
            let savedURL = try OutputHandler().save(gifAt: gifURL, toFolder: folder)
            print("[GifBar] GIF saved to: \(savedURL.path)")
            if preferences.preferences.revealInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            }
            return savedURL
        } catch {
            print("[GifBar] failed to save GIF to folder: \(error)")
            return gifURL
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
