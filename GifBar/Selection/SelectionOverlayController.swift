//
//  SelectionOverlayController.swift
//  GifBar
//
//  Iteration 2 — Selection overlay (SPEC §4.2).
//

import AppKit
import Observation
import SwiftUI

/// Observable, live geometry of the selection panel that the SwiftUI overlay
/// binds to. Updated by ``SelectionOverlayController`` on every resize.
@Observable
@MainActor
final class SelectionOverlayModel {
    /// Current panel size in points.
    var size: CGSize = .zero
}

/// Creates, presents, and tears down the floating selection panel, and reports
/// the chosen area back to its owner.
///
/// This is one of the few reference types allowed by SPEC §3: an AppKit
/// coordinator whose lifetime must outlive the value-typed SwiftUI views.
@MainActor
final class SelectionOverlayController {
    /// Called when the user confirms a selection (Return / Space). The rect is
    /// already converted to top-left capture coordinates.
    var onCommit: ((CGRect) -> Void)?
    /// Called when the user cancels the selection (Esc).
    var onCancel: (() -> Void)?

    private let model = SelectionOverlayModel()
    private var panel: SelectionPanel?
    private var resizeObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    /// Default size of a fresh selection, in points.
    private let defaultSize = CGSize(width: 640, height: 400)

    // MARK: - Presentation

    /// Shows the selection panel, centered on the active screen. Calling this
    /// while a panel is already visible just brings the existing one forward.
    func present() {
        if let panel {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = centeredFrame(size: defaultSize, in: screen)

        let panel = SelectionPanel(
            contentRect: frame,
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.setFrame(frame, display: true)

        let host = NSHostingView(rootView: SelectionOverlayView(model: model))
        panel.contentView = host

        model.size = frame.size
        observeResize(of: panel)
        installKeyMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    /// Hides and disposes the panel along with its observers.
    func dismiss() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        resizeObserver = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil

        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Configuration

    private func configure(_ panel: SelectionPanel) {
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.minSize = SelectionGeometry.minimumSize
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func centeredFrame(size: CGSize, in screen: NSScreen?) -> CGRect {
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Live updates & input

    private func observeResize(of panel: SelectionPanel) {
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.size = panel.frame.size
            }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // Esc
                self.cancel()
                return nil
            case 36, 76, 49: // Return, keypad Enter, Space
                self.commit()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: - Actions

    private func commit() {
        guard let panel else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? panel.frame.maxY
        let captureRect = SelectionGeometry.captureRect(
            fromAppKitFrame: panel.frame,
            primaryScreenHeight: primaryHeight
        )
        // TODO: Iteration 4 — hand this rect to the capture pipeline.
        print("[GifBar] selection committed (capture coords): \(captureRect)")
        onCommit?(captureRect)
        dismiss()
    }

    private func cancel() {
        print("[GifBar] selection cancelled")
        onCancel?()
        dismiss()
    }
}
