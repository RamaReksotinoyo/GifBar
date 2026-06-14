//
//  SelectionOverlayView.swift
//  GifBar
//
//  Iteration 2 — Selection overlay (SPEC §4.2).
//

import SwiftUI

/// The visual content of the selection panel: a translucent fill, an accent
/// border, and a live "W × H" readout that updates as the panel is resized.
struct SelectionOverlayView: View {
    /// Live geometry of the panel, updated by ``SelectionOverlayController``.
    var model: SelectionOverlayModel

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)

            Text(SelectionGeometry.dimensionLabel(for: model.size))
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .ignoresSafeArea()
    }
}
