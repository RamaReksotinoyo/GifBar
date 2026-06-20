//
//  PreferencesView.swift
//  GifBar
//
//  Iteration 7d — Preferences panel (SPEC §4.5 / §4.6).
//
//  The app's Settings scene: frame rate, save folder, and output toggles, all
//  bound to `PreferencesStore` so changes persist immediately.
//

import SwiftUI
import AppKit

/// Settings panel for GifBar. Reads and writes ``PreferencesStore`` directly;
/// every control persists on change, so there is no explicit "Save" button.
struct PreferencesView: View {
    let preferences: PreferencesStore

    var body: some View {
        Form {
            Section("Recording") {
                Picker("Frame rate", selection: fpsBinding) {
                    ForEach(RecordingState.FrameRate.allCases, id: \.self) { fps in
                        Text("\(fps.rawValue) fps").tag(fps)
                    }
                }
            }

            Section("Output") {
                LabeledContent("Save folder") {
                    HStack(spacing: 8) {
                        Text(folderDisplay)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseSaveFolder() }
                    }
                }
                Toggle("Reveal in Finder after saving", isOn: revealBinding)
                Toggle("Copy to Clipboard", isOn: clipboardBinding)
            }
        }
        .formStyle(.grouped)
        // An explicit size: hosted in a plain NSWindow, a grouped Form has no
        // outer container to stretch into, so without this the window collapses
        // to a height that clips the top section.
        .frame(width: 440, height: 300)
    }

    // MARK: - Bindings

    private var fpsBinding: Binding<RecordingState.FrameRate> {
        Binding(get: { preferences.preferences.fps },
                set: { preferences.setFPS($0) })
    }

    private var revealBinding: Binding<Bool> {
        Binding(get: { preferences.preferences.revealInFinder },
                set: { preferences.setRevealInFinder($0) })
    }

    private var clipboardBinding: Binding<Bool> {
        Binding(get: { preferences.preferences.copyToClipboard },
                set: { preferences.setCopyToClipboard($0) })
    }

    // MARK: - Save folder

    /// Path of the currently chosen save folder, or a placeholder if unset.
    private var folderDisplay: String {
        preferences.resolveSaveFolder()?.url.path(percentEncoded: false) ?? "Not set"
    }

    /// Lets the user pick the folder finished GIFs are saved to, persisting the
    /// choice as a security-scoped bookmark (SPEC §4.6).
    private func chooseSaveFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where GifBar saves recorded GIFs."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try preferences.setSaveFolder(url)
        } catch {
            print("[GifBar] failed to save folder bookmark: \(error)")
        }
    }
}
