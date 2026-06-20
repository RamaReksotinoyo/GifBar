//
//  OutputHandler.swift
//  GifBar
//
//  Iteration 6 — Output handler (SPEC §4.6).
//
//  Moves a finished GIF out of the temp directory into the user's chosen save
//  folder under a timestamped, collision-free name. Pure file I/O: the caller
//  is responsible for security-scoped access around the folder (sandbox).
//

import Foundation

/// Saves finished GIFs to a destination folder.
///
/// `nonisolated`: plain file work, safe off the main actor. Holds no state, so
/// the same instance can be reused.
nonisolated struct OutputHandler {
    enum OutputError: Error {
        /// The destination folder could not be created.
        case cannotCreateFolder(Error)
        /// Moving the GIF into place failed.
        case cannotMoveFile(Error)
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Moves `gifURL` into `folder` under a timestamped name, returning the
    /// final URL.
    ///
    /// The folder is created if missing. If a file with the chosen name already
    /// exists, a ` (2)`, ` (3)`… suffix is appended so nothing is overwritten.
    ///
    /// - Note: When sandboxed, the caller must hold security-scoped access to
    ///   `folder` for the duration of this call.
    func save(gifAt gifURL: URL, toFolder folder: URL, date: Date = Date()) throws -> URL {
        if !fileManager.fileExists(atPath: folder.path) {
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw OutputError.cannotCreateFolder(error)
            }
        }

        let destination = uniqueURL(in: folder, baseName: Self.fileName(for: date))
        do {
            try fileManager.moveItem(at: gifURL, to: destination)
        } catch {
            throw OutputError.cannotMoveFile(error)
        }
        return destination
    }

    // MARK: - Naming

    /// A filename like `GifBar 2026-06-17 at 14.32.45.gif`. Uses dots instead of
    /// colons, which are illegal in macOS file names.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "GifBar \(formatter.string(from: date)).gif"
    }

    /// Returns `folder/baseName`, inserting a ` (n)` suffix before the extension
    /// if needed so the result does not already exist.
    private func uniqueURL(in folder: URL, baseName: String) -> URL {
        let candidate = folder.appendingPathComponent(baseName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let url = folder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}
