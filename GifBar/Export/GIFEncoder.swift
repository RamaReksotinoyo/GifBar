//
//  GIFEncoder.swift
//  GifBar
//
//  Iteration 5 — GIF conversion engine (SPEC §4.5).
//
//  A thin, pure wrapper around ImageIO's CGImageDestination. It knows nothing
//  about movies or capture: callers feed it CGImages one at a time and it
//  streams them straight into a `.gif` file, so RAM stays flat regardless of
//  how long the recording is (SPEC §4.4 philosophy).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Streams `CGImage` frames into an animated GIF on disk.
///
/// `nonisolated`: encoding is CPU work that runs off the main actor, on the
/// same task that decodes the source movie (see ``MovieToGIFConverter``).
/// Usage is strictly sequential — `append` repeatedly, then `finalize` once.
nonisolated struct GIFEncoder {
    enum EncoderError: Error {
        /// ImageIO could not create a destination for the output URL.
        case cannotCreateDestination
    }

    /// Destination URL of the GIF being written.
    let outputURL: URL

    private let destination: CGImageDestination

    /// Number of frames appended so far; used to avoid finalizing an empty GIF.
    private(set) var frameCount = 0

    /// Creates a GIF destination that loops forever.
    ///
    /// - Parameter capacity: The maximum number of frames the GIF will hold.
    ///   ImageIO treats this as a hard cap, not a hint: appending *more* than
    ///   `capacity` frames makes ``finalize()`` fail. Appending fewer is fine.
    ///   Pass an exact count or a safe upper bound.
    init(outputURL: URL, capacity: Int = 1) throws {
        self.outputURL = outputURL

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            max(1, capacity),
            nil
        ) else {
            throw EncoderError.cannotCreateDestination
        }
        self.destination = destination

        // File-level property: loop count 0 == loop indefinitely.
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
    }

    /// Appends one frame shown for `delaySeconds`.
    ///
    /// GIF only stores delays at centisecond resolution (SPEC §4.5), so the
    /// requested delay is rounded to the nearest 1/100 s. We set both the
    /// clamped and unclamped delay keys: viewers that ignore very short clamped
    /// delays still honour the unclamped value.
    ///
    /// Note on dithering: ImageIO quantizes each frame down to the GIF's 256-
    /// colour palette and applies dithering internally during that step. There
    /// is no public key to toggle Floyd–Steinberg specifically, so the SPEC §4.5
    /// "dithering via kCGImagePropertyGIFDictionary" is satisfied by ImageIO's
    /// built-in quantizer rather than an explicit flag.
    mutating func append(_ image: CGImage, delaySeconds: Double) {
        let centiseconds = (delaySeconds * 100).rounded() / 100
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: centiseconds,
                kCGImagePropertyGIFUnclampedDelayTime: centiseconds
            ]
        ]
        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        frameCount += 1
    }

    /// Writes the GIF to disk. Returns `false` (and leaves no file) if no frames
    /// were ever appended, mirroring ``MovieWriter/finish()``.
    @discardableResult
    func finalize() -> Bool {
        guard frameCount > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            return false
        }
        return CGImageDestinationFinalize(destination)
    }
}
