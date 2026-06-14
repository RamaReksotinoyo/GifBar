//
//  CaptureConfiguration.swift
//  GifBar
//
//  Iteration 4a — Capture pipeline (SPEC §4.4).
//
//  Pure derivation of ScreenCaptureKit parameters from the user's selection.
//  No ScreenCaptureKit / AppKit here, so all the math is unit testable; the
//  coordinator (4b) feeds in the real display frame & scale.
//

import CoreGraphics
import CoreMedia

/// Concrete capture parameters derived from a selection rect, the target
/// display, and the chosen frame rate.
nonisolated struct CaptureConfiguration: Equatable {
    /// Crop rect in points, relative to the captured display's origin
    /// (top-left). Maps onto `SCStreamConfiguration.sourceRect`.
    var sourceRect: CGRect
    /// Output width in pixels (points × scale, rounded to an even number).
    var pixelWidth: Int
    /// Output height in pixels (points × scale, rounded to an even number).
    var pixelHeight: Int
    /// Minimum interval between frames; maps onto
    /// `SCStreamConfiguration.minimumFrameInterval`.
    var frameInterval: CMTime

    /// Builds a configuration for `selectedRect` (global, top-left points)
    /// captured from a display whose `displayFrame` is also in global
    /// top-left points.
    ///
    /// - Parameters:
    ///   - selectedRect: The chosen area in global capture coordinates.
    ///   - displayFrame: The target display's frame in global coordinates.
    ///   - scaleFactor: Pixels per point for that display (e.g. `2.0` Retina).
    ///   - fps: The chosen capture frame rate.
    static func make(selectedRect: CGRect,
                     displayFrame: CGRect,
                     scaleFactor: CGFloat,
                     fps: RecordingState.FrameRate) -> CaptureConfiguration {
        let source = CGRect(
            x: selectedRect.minX - displayFrame.minX,
            y: selectedRect.minY - displayFrame.minY,
            width: selectedRect.width,
            height: selectedRect.height
        )
        return CaptureConfiguration(
            sourceRect: source,
            pixelWidth: evenPixels(selectedRect.width, scale: scaleFactor),
            pixelHeight: evenPixels(selectedRect.height, scale: scaleFactor),
            frameInterval: CMTime(value: 1, timescale: CMTimeScale(fps.rawValue))
        )
    }

    /// Picks the index of the display that contains most of `rect`, by overlap
    /// area. Returns `nil` if there are no displays or no overlap at all.
    static func bestDisplayIndex(for rect: CGRect,
                                 among displayFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in displayFrames.enumerated() {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// Converts a points dimension to pixels, rounded up to the nearest even
    /// number. H.264 requires even width/height.
    private static func evenPixels(_ points: CGFloat, scale: CGFloat) -> Int {
        let raw = Int((points * scale).rounded())
        return raw.isMultiple(of: 2) ? raw : raw + 1
    }
}
