//
//  SCStreamCoordinator.swift
//  GifBar
//
//  Iteration 4b — Capture pipeline (SPEC §4.4).
//
//  The single Objective-C-bridged reference type allowed by SPEC §3: the
//  ScreenCaptureKit delegate. It owns the live SCStream, routes each frame to
//  the MovieWriter on a dedicated queue, and hands back the finished temp .mov.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Drives a ScreenCaptureKit stream for a selected region and writes frames to
/// a temp `.mov`.
///
/// `nonisolated` + `@unchecked Sendable`: ScreenCaptureKit delivers frames on
/// `sampleQueue` (off the main actor), so the type cannot be `@MainActor`.
/// Access to `stream`/`writer` is effectively serialized — they are set during
/// `start()` before any frame arrives and torn down in `stop()`.
nonisolated final class SCStreamCoordinator: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {

    enum CaptureError: Error {
        /// The selection rect did not overlap any available display.
        case noMatchingDisplay
    }

    /// ScreenCaptureKit reports a normal `stopCapture()` as this error code in
    /// `didStopWithError`; it is expected, not a failure.
    private static let userStoppedCode = -3817

    private let sampleQueue = DispatchQueue(label: "com.iswift.GifBar.capture")
    private var stream: SCStream?
    private var writer: MovieWriter?

    /// Guards `stream`/`hasStopped`, which are touched from both the stop task
    /// and the delegate callback queue.
    private let lock = NSLock()
    private var hasStopped = false

    /// URL of the temp movie for the current/last recording.
    private(set) var outputURL: URL?

    // MARK: - Lifecycle

    /// Begins capturing `captureRect` (global, top-left points) at `fps`.
    func start(captureRect: CGRect, fps: RecordingState.FrameRate) async throws {
        let content = try await SCShareableContent.current

        let displayFrames = content.displays.map(\.frame)
        guard let index = CaptureConfiguration.bestDisplayIndex(for: captureRect, among: displayFrames) else {
            throw CaptureError.noMatchingDisplay
        }
        let display = content.displays[index]

        let scale = scaleFactor(for: display)
        let config = CaptureConfiguration.make(
            selectedRect: captureRect,
            displayFrame: display.frame,
            scaleFactor: scale,
            fps: fps
        )

        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.pixelWidth
        streamConfig.height = config.pixelHeight
        streamConfig.sourceRect = config.sourceRect
        streamConfig.minimumFrameInterval = config.frameInterval
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.showsCursor = true
        streamConfig.queueDepth = 6

        // Keep GifBar's own windows out of the recording (SPEC §4.4 note).
        let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApp.map { [$0] } ?? [],
            exceptingWindows: []
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-\(UUID().uuidString).mov")
        let writer = try MovieWriter(
            outputURL: url,
            pixelWidth: config.pixelWidth,
            pixelHeight: config.pixelHeight,
            frameRate: Int(fps.rawValue)
        )
        self.writer = writer
        self.outputURL = url

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream

        try await stream.startCapture()
    }

    /// Stops capturing and finalizes the movie, returning its URL.
    ///
    /// Safe to call once even if the stream already stopped on its own: the
    /// `hasStopped` guard avoids a redundant `stopCapture()` (which SCK logs as
    /// error -3808).
    func stop() async -> URL? {
        let streamToStop: SCStream? = lock.withLock {
            guard !hasStopped else { return nil }
            hasStopped = true
            let current = stream
            stream = nil
            return current
        }

        if let streamToStop {
            try? await streamToStop.stopCapture()
        }
        await writer?.finish()

        let url = outputURL
        writer = nil
        return url
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, let writer, sampleBuffer.isValid else { return }
        guard frameIsComplete(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // A dropped frame here (writer not ready) keeps its timestamp; the next
        // accepted frame simply lands later on the timeline (SPEC §4.5).
        writer.append(imageBuffer, at: pts)
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // A normal stopCapture() surfaces here as -3817 ("user stopped"); ignore.
        if (error as NSError).code == Self.userStoppedCode { return }

        // The stream died on its own (e.g. display disconnected). Mark it
        // stopped so a later stop() won't double-call stopCapture.
        // TODO: Iteration 4+ — notify RecordingStore so it can leave .recording.
        print("[GifBar] stream stopped unexpectedly: \(error)")
        lock.withLock { hasStopped = true }
    }

    // MARK: - Helpers

    /// ScreenCaptureKit emits blank/idle frames between updates; only
    /// `.complete` frames carry pixels worth writing.
    private func frameIsComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = array.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else {
            return false
        }
        return status == .complete
    }

    /// Pixels-per-point for the display, computed without touching AppKit so it
    /// is safe off the main actor.
    private func scaleFactor(for display: SCDisplay) -> CGFloat {
        guard display.width > 0 else { return 1 }
        return CGFloat(CGDisplayPixelsWide(display.displayID)) / CGFloat(display.width)
    }
}
