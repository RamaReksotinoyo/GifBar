//
//  ClipboardWriter.swift
//  GifBar
//
//  Iteration 7b — Copy-to-Clipboard (SPEC §4.6).
//
//  Places a finished GIF on the system pasteboard so the user can paste it
//  straight into chat apps, editors, or documents.
//

import AppKit
import UniformTypeIdentifiers

/// Writes a GIF to an `NSPasteboard`.
///
/// `@MainActor`: `NSPasteboard` is AppKit UI state. The pasteboard is injectable
/// so tests can use a private, named pasteboard instead of the real clipboard.
@MainActor
struct ClipboardWriter {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Copies a GIF to the pasteboard, exposing it two ways in a single item so
    /// different apps can each find a representation they accept:
    ///
    /// - a **file URL**, for apps that paste files (Finder, many chat clients);
    /// - the **raw GIF data**, for apps that paste images inline.
    ///
    /// Takes the data directly rather than reading `fileURL`: the GIF may live in
    /// a security-scoped folder that is no longer accessible by the time this is
    /// called, so the caller reads the bytes while access is still valid.
    ///
    /// - Returns: `true` if the pasteboard accepted the item.
    @discardableResult
    func writeGIF(data: Data, fileURL: URL) -> Bool {
        let item = NSPasteboardItem()
        item.setData(fileURL.dataRepresentation, forType: .fileURL)
        item.setData(data, forType: Self.gifType)

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    /// Convenience that reads the GIF at `url` and copies it. Only safe for URLs
    /// readable without security scope (temp files, test fixtures); the store
    /// uses ``writeGIF(data:fileURL:)`` for security-scoped destinations.
    ///
    /// - Returns: `true` on success; `false` if the GIF could not be read.
    @discardableResult
    func writeGIF(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return writeGIF(data: data, fileURL: url)
    }

    /// Pasteboard type for GIF data (`com.compuserve.gif`).
    static let gifType = NSPasteboard.PasteboardType(UTType.gif.identifier)
}
