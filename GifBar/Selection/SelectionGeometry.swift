//
//  SelectionGeometry.swift
//  GifBar
//
//  Iteration 2 — Selection overlay (SPEC §4.2).
//
//  Pure, side-effect-free geometry helpers for the selection overlay. Kept
//  separate from the AppKit panel so the coordinate math can be unit tested.
//

import CoreGraphics
import Foundation

/// Namespace for selection-rectangle geometry calculations.
enum SelectionGeometry {
    /// The smallest selection the user is allowed to make, in points.
    static let minimumSize = CGSize(width: 80, height: 60)

    /// Converts an AppKit window frame into a top-left-origin capture rect.
    ///
    /// AppKit uses a bottom-left origin with the Y axis pointing up, whereas
    /// CoreGraphics and ScreenCaptureKit use a top-left origin with the Y axis
    /// pointing down. The flip is performed against the primary screen height
    /// (the screen whose bottom-left is the global origin), which keeps the
    /// result correct even for displays positioned above the primary one
    /// (their capture `y` becomes negative, matching CoreGraphics).
    ///
    /// - Parameters:
    ///   - frame: The panel frame in AppKit global coordinates.
    ///   - primaryScreenHeight: Height of the primary screen, in points.
    /// - Returns: The equivalent rect in top-left (capture) coordinates.
    static func captureRect(fromAppKitFrame frame: CGRect,
                            primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// Grows a rect (from its origin) so neither dimension is below
    /// ``minimumSize``. Rects already large enough are returned unchanged.
    static func enforcingMinimumSize(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: max(rect.width, minimumSize.width),
            height: max(rect.height, minimumSize.height)
        )
    }

    /// Formats a size as a "W × H" label using whole points, e.g. `"640 × 400"`.
    static func dimensionLabel(for size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(width) × \(height)"
    }
}
