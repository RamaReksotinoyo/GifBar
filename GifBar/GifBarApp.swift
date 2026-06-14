//
//  GifBarApp.swift
//  GifBar
//
//  Created by Anugrah Tri Ramadhan on 14/06/26.
//

import SwiftUI
import AppKit

@main
struct GifBarApp: App {
    var body: some Scene {
        MenuBarExtra("GifBar", systemImage: "record.circle") {
            Button("Record Area") {
                // TODO: Iteration 2 — Display the selection overlay
            }

            Button("Preferences…") {
                // TODO: Iteration 7 — open the panel Preferences
            }

            Divider()

            Button("Quit GifBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
