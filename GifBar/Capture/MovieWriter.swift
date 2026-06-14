//
//  MovieWriter.swift
//  GifBar
//
//  Iteration 4a — Capture pipeline (SPEC §4.4).
//
//  Thin wrapper around AVAssetWriter that streams frames straight to a temp
//  `.mov` so RAM stays flat regardless of recording length. Marked
//  `nonisolated` so the capture callback (4b) can append frames off the main
//  actor, which is where ScreenCaptureKit delivers them.
//

import AVFoundation
import CoreMedia
import CoreVideo

/// Writes incoming pixel buffers to a hardware-encoded `.mov` file.
nonisolated final class MovieWriter {
    enum WriterError: Error {
        case cannotAddInput
    }

    /// Location of the temp movie being written.
    let outputURL: URL

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var hasStarted = false

    /// Whether the writer can currently accept another frame. When `false`,
    /// callers should drop the frame (SPEC §4.5: drop frame, keep timestamp).
    var isReady: Bool { hasStarted && input.isReadyForMoreMediaData }

    /// - Parameter realtime: When `true` (the default, used for live capture)
    ///   the encoder favours keeping up over completeness and may drop or pad
    ///   frames. Tests pass `false` for a deterministic 1-frame-in, 1-frame-out
    ///   mapping.
    init(outputURL: URL, pixelWidth: Int, pixelHeight: Int, frameRate: Int,
         realtime: Bool = true) throws {
        self.outputURL = outputURL
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = realtime

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: bufferAttributes
        )

        guard writer.canAdd(input) else { throw WriterError.cannotAddInput }
        writer.add(input)
    }

    /// Appends one frame at the given presentation time. The writing session is
    /// started lazily on the first frame so its timeline begins at `time`.
    ///
    /// - Returns: `true` if the frame was written, `false` if it was dropped
    ///   (writer not ready) or could not be appended.
    @discardableResult
    func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) -> Bool {
        if !hasStarted {
            guard writer.startWriting() else { return false }
            writer.startSession(atSourceTime: time)
            hasStarted = true
        }
        guard input.isReadyForMoreMediaData else { return false }
        return adaptor.append(pixelBuffer, withPresentationTime: time)
    }

    /// Finalizes the file. Safe to call even if no frames were appended.
    func finish() async {
        guard hasStarted else {
            writer.cancelWriting()
            return
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
