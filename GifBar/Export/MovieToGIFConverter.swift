//
//  MovieToGIFConverter.swift
//  GifBar
//
//  Iteration 5 — GIF conversion engine (SPEC §4.5).
//
//  Orchestrates the .mov → .gif conversion: decode the temp movie one frame at
//  a time and hand each frame to a GIFEncoder. Each decode iteration runs inside
//  an `autoreleasepool` so per-frame temporaries are freed immediately instead
//  of accumulating across the loop (SPEC §4.4).
//
//  Caveat: this caps the decode side at ~one frame, but ImageIO's
//  CGImageDestination still buffers every appended frame until `finalize()`
//  (it does not stream GIF to disk), so peak memory still grows with frame
//  count — just far less than before the autoreleasepool.
//

import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

/// Converts a temp `.mov` recording into an animated `.gif` at a target frame
/// rate, applying SPEC §4.5's frame-dropping strategy.
///
/// `nonisolated`: all work (decode + encode) runs off the main actor.
nonisolated struct MovieToGIFConverter {
    enum ConversionError: Error {
        /// The source movie had no decodable video track.
        case noVideoTrack
        /// AVAssetReader failed to start or finished in a failed state.
        case readerFailed(Error?)
        /// The GIF was opened but no frames could be decoded/encoded.
        case noFramesEncoded
    }

    /// Reuse one CIContext across all frames — creating one per frame is the
    /// classic Core Image performance trap.
    private let ciContext = CIContext(options: nil)

    /// Decodes `movieURL` and writes a looping GIF at `fps`, returning its URL.
    ///
    /// Frame-dropping (SPEC §4.5): the output timeline advances in fixed
    /// `1/fps` steps. A decoded frame is emitted only once its presentation
    /// time has reached the next slot; extra frames are dropped rather than
    /// stretching delays, so playback speed matches real time.
    func convert(movieURL: URL, fps: RecordingState.FrameRate) async throws -> URL {
        let asset = AVURLAsset(url: movieURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        guard reader.canAdd(output) else { throw ConversionError.readerFailed(nil) }
        reader.add(output)
        guard reader.startReading() else { throw ConversionError.readerFailed(reader.error) }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gifbar-\(UUID().uuidString).gif")

        // GIFEncoder needs a hard upper bound on frame count. We emit at most
        // one frame per output slot, so duration × fps (plus margin) is safe.
        let duration = try await asset.load(.duration).seconds
        let capacity = max(1, Int((duration * Double(fps.rawValue)).rounded(.up)) + 2)
        var encoder = try GIFEncoder(outputURL: outputURL, capacity: capacity)

        let frameDelay = 1.0 / Double(fps.rawValue)
        var nextEmitTime = 0.0

        while let sample = output.copyNextSampleBuffer() {
            // Drain each frame's temporaries (CIImage, the decoded CGImage, Core
            // Image's working buffers) immediately. In an async function the
            // thread's autorelease pool is not drained until `convert` returns,
            // so without this every decoded frame would pile up and memory would
            // grow with the recording length. `return` here acts as `continue`.
            autoreleasepool {
                defer { CMSampleBufferInvalidate(sample) }
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { return }

                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                // Drop frames that arrive before the next output slot; keep the
                // timeline (don't stretch the delay of the frames we do keep).
                guard pts >= nextEmitTime else { return }

                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    return
                }
                encoder.append(cgImage, delaySeconds: frameDelay)
                nextEmitTime += frameDelay
            }
        }

        if reader.status == .failed {
            throw ConversionError.readerFailed(reader.error)
        }
        guard encoder.finalize() else {
            throw ConversionError.noFramesEncoded
        }
        return outputURL
    }
}
