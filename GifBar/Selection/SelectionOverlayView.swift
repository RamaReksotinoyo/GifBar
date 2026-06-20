//
//  SelectionOverlayView.swift
//  GifBar
//
//  Iteration 2 — Selection overlay (SPEC §4.2).
//

import SwiftUI

/// The visual content of the selection panel: a translucent fill, an accent
/// border, a live "W × H" readout, and a keyboard hint — all centered in a
/// single pill that updates as the panel is resized.
struct SelectionOverlayView: View {
    /// Live geometry of the panel, updated by ``SelectionOverlayController``.
    var model: SelectionOverlayModel

    /// Below this width the panel is too narrow to fit the hint without
    /// clipping, so only the dimension readout is shown.
    static let hintMinimumWidth: CGFloat = 220

    /// Whether the keyboard hint should be shown for a panel of the given width.
    /// Extracted as a pure function so the threshold logic is unit-testable.
    static func shouldShowHint(forWidth width: CGFloat) -> Bool {
        width >= hintMinimumWidth
    }

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)

            VStack(spacing: 6) {
                Text(SelectionGeometry.dimensionLabel(for: model.size))
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()

                if Self.shouldShowHint(forWidth: model.size.width) {
                    Text("⏎ / Space to start · Esc to cancel")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .ignoresSafeArea()
    }
}
