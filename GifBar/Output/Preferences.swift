//
//  Preferences.swift
//  GifBar
//
//  Iteration 6 — Output handler (SPEC §4.6).
//
//  User-configurable output settings. A value type per SPEC §3.2; the
//  observable shell (`PreferencesStore`) persists it and resolves the
//  security-scoped bookmark that lets a sandboxed app write to a folder the
//  user picked.
//

import Foundation

/// Persisted output preferences.
///
/// The save destination is stored as a **security-scoped bookmark** rather than
/// a plain path: under App Sandbox, a raw path the user picked is not writable
/// across launches — only a bookmark re-grants access (SPEC §2 / App Store).
struct Preferences: Equatable, Sendable {
    /// Bookmark data for the user-chosen save folder, or `nil` if never set
    /// (falls back to the app's own Documents directory).
    var folderBookmark: Data?

    /// Reveal each finished GIF in Finder after saving.
    var revealInFinder: Bool = true
}

/// Observable store that loads/saves ``Preferences`` and resolves the save
/// folder. The only reference type here (SPEC §3 coordinator exception), needed
/// so SwiftUI can observe preference changes.
@Observable
@MainActor
final class PreferencesStore {
    private enum Key {
        static let folderBookmark = "output.folderBookmark"
        static let revealInFinder = "output.revealInFinder"
    }

    /// Current preferences. Mutated only through the methods below so each
    /// change is persisted.
    private(set) var preferences: Preferences

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var prefs = Preferences()
        prefs.folderBookmark = defaults.data(forKey: Key.folderBookmark)
        if defaults.object(forKey: Key.revealInFinder) != nil {
            prefs.revealInFinder = defaults.bool(forKey: Key.revealInFinder)
        }
        self.preferences = prefs
    }

    // The synthesized deinit of a `@MainActor` class is main-actor-isolated,
    // which routes through the concurrency back-deploy runtime on macOS 14 and
    // hits a libmalloc double-free during teardown. Nothing here needs main-
    // actor isolation to release, so opt the deinit out.
    nonisolated deinit {}

    /// Records the folder the user picked, storing a security-scoped bookmark so
    /// access survives relaunches.
    func setSaveFolder(_ url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        preferences.folderBookmark = bookmark
        defaults.set(bookmark, forKey: Key.folderBookmark)
    }

    func setRevealInFinder(_ reveal: Bool) {
        preferences.revealInFinder = reveal
        defaults.set(reveal, forKey: Key.revealInFinder)
    }

    /// Resolves the saved bookmark to a usable folder URL, or `nil` if none is
    /// set or it can no longer be resolved (e.g. the folder was deleted).
    ///
    /// - Returns: A tuple of the folder URL and whether the bookmark was stale
    ///   (the caller should re-save it if so). The URL has security scope that
    ///   the caller must `startAccessingSecurityScopedResource()` before use.
    func resolveSaveFolder() -> (url: URL, isStale: Bool)? {
        guard let bookmark = preferences.folderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (url, isStale)
    }
}
