# GifBar

A native macOS menu bar utility that records a selected screen area and exports it straight to `.gif`. Built for developers who need quick demos for GitHub READMEs and docs, with a focus on high performance, minimal RAM usage, and a minimalist UI.

## Features

-  Record any screen area and export to GIF
-  Selectable frame rates: 10 / 15 / 24 FPS
-  Save to a folder or copy directly to the clipboard
-  Lives in the menu bar — no Dock clutter

## Requirements

- macOS 14 (Sonoma) or later
- Screen Recording permission

## Tech Stack

- **Swift** + **SwiftUI** (menu bar extra)
- **ScreenCaptureKit** for screen capture
- **AVFoundation** for frame processing
- **ImageIO** for GIF export

## Build

```bash
xcodebuild -project GifBar.xcodeproj -scheme GifBar -configuration Debug build
```

Or open `GifBar.xcodeproj` in Xcode and run.

## Status

🚧 Under development.

## License

TBD
