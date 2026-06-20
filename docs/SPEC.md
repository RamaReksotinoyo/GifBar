# App Specification Brief: GifBar — macOS Native Screen-to-GIF Recorder

## 1. Overview

GifBar adalah aplikasi macOS utility modern yang berfungsi merekam area layar tertentu dan langsung mengekspornya ke format `.gif`. Ditujukan untuk developer (kebutuhan demo di README GitHub, dokumentasi, dll) dengan fokus pada **performa tinggi**, **penggunaan RAM minimal**, dan **UI yang minimalis**.

---

## 2. Core Tech Stack & Architecture

| Komponen | Pilihan | Alasan |
|---|---|---|
| Platform | macOS 14+ (Sonoma+) | `ScreenCaptureKit` API stabil di 14+ |
| Language | Swift | Native performance, value types idiomatik |
| UI Framework | SwiftUI (100% Native) | `View` adalah `struct` by default — cache-friendly |
| UX Pattern | Menu Bar Extra Utility | Ala Kap / Amphetamine — tidak mengotori Dock |
| Screen Capture | `ScreenCaptureKit` | Jauh lebih efisien dari `CGWindowListCreateImage` lama |
| Frame Processing | `AVFoundation` + `CMSampleBuffer` | Zero-copy buffer handling di hot path |
| GIF Export | `ImageIO` | Native, zero dependency eksternal |

**Distribution:** Direct distribution (notarized, bukan App Store) — menghindari sandbox restriction pada akses temp directory dan clipboard.

> **REVISI (Iterasi 6):** Keputusan ini **dibalik** — App Sandbox **tetap ON**
> (`ENABLE_APP_SANDBOX = YES`) demi membuka peluang distribusi via Mac App Store.
> Konsekuensi yang sudah ditangani: save ke folder pilihan user memakai
> **security-scoped bookmark** (`ENABLE_USER_SELECTED_FILES = readwrite`).
> ScreenCaptureKit & clipboard tetap jalan di sandbox. **Dampak ke Iterasi 7:**
> global shortcut (`NSEvent.addGlobalMonitorForEvents`) kemungkinan terbatas di
> sandbox/App Store — perlu dievaluasi ulang di iterasi itu.

---

## 3. Design Philosophy: Data-Oriented, Value-First

### 3.1 Prinsip Utama

- **Struct everywhere di UI layer** — semua SwiftUI `View` adalah `struct`, tidak ada class kecuali untuk delegate/coordinator yang memang wajib reference type
- **No dynamic dispatch di hot path** — gunakan **generics (`some Protocol`)**, bukan **existentials (`any Protocol`)**, agar compiler dapat melakukan static dispatch dan inlining
- **Flat, contiguous memory untuk frame buffer** — rancang `FrameBuffer` dengan Struct of Arrays (SoA) pattern, bukan Array of Structs (AoS)
- **Satu class terisolasi** — `SCStreamCoordinator` (delegate `SCStream`) adalah satu-satunya reference type yang diizinkan, karena Objective-C bridging memerlukannya

### 3.2 Layer Architecture

```
┌─────────────────────────────────────────────────────┐
│  Layer               │  Type         │  Rationale   │
├─────────────────────────────────────────────────────┤
│  SwiftUI Views       │  struct       │  Default,    │
│  (MenuBarView,       │               │  idiomatik   │
│  OverlayView, etc.)  │               │  SwiftUI     │
├─────────────────────────────────────────────────────┤
│  App State           │  struct +     │  Value       │
│  (RecordingState,    │  enum         │  semantics,  │
│  Preferences)        │               │  Sendable    │
├─────────────────────────────────────────────────────┤
│  SCStream            │  class        │  WAJIB:      │
│  Coordinator         │  (1 saja)     │  ObjC bridge │
│                      │               │  delegate    │
├─────────────────────────────────────────────────────┤
│  Frame Pipeline      │  actor        │  Thread-safe │
│  (buffer, convert,   │               │  tanpa manual│
│  write)              │               │  locking     │
├─────────────────────────────────────────────────────┤
│  GIF Encoder         │  struct +     │  Pure func,  │
│                      │  static func  │  no state,   │
│                      │               │  inlineable  │
└─────────────────────────────────────────────────────┘
```

### 3.3 FrameBuffer: Struct of Arrays (SoA) Pattern

Hot path aplikasi ini ada di frame processing callback (`SCStreamOutput`), yang dipanggil hingga 24x/detik. `FrameBuffer` dirancang untuk cache locality:

```swift
// ❌ Array of Structs — pointer chase tiap akses frame
struct Frame {
    var timestamp: Double
    var pixelData: [UInt8]   // heap allocated per frame
}

// ✅ Struct of Arrays — contiguous, cache-friendly
struct FrameBuffer {
    var timestamps: [Double]      // contiguous block
    var widths:     [UInt16]      // contiguous block
    var heights:    [UInt16]      // contiguous block
    var offsets:    [Int]         // index ke pixelPool
    var pixelPool:  [UInt8]       // satu flat buffer, zero fragmentation

    mutating func append(timestamp: Double, width: UInt16,
                         height: UInt16, pixels: UnsafeBufferPointer<UInt8>) {
        timestamps.append(timestamp)
        widths.append(width)
        heights.append(height)
        offsets.append(pixelPool.count)
        pixelPool.append(contentsOf: pixels)
    }
}
```

### 3.4 No Dynamic Dispatch di Pipeline

```swift
// ❌ Existential — witness table dispatch + heap allocation
func encode(converter: any GIFConverter) { }

// ✅ Generic — static dispatch, compiler bisa inline
func encode<C: GIFConverter>(converter: C) { }
```

---

## 4. Core Features & User Workflow

### 4.1 Menu Bar Extra

Aplikasi menetap di menu bar. Klik ikon memunculkan menu:
- **Record Area** — memulai selection overlay
- **Preferences** — buka panel pengaturan
- **Quit**

### 4.2 Floating Selection Overlay

Saat klik "Record Area", muncul `NSPanel` dengan level `.floating` (bukan `.borderless NSWindow`) yang dapat di-resize untuk menentukan koordinat area `(X, Y, Width, Height)`.

Alasan `NSPanel` bukan `NSWindow`:
- Dapat muncul di atas semua window termasuk fullscreen app
- Tidak "mencuri" key events dari aplikasi lain

### 4.3 Recording Lifecycle

```
[Idle] → "Record Area" → [Selecting] → "Start" → [Recording] → "Stop" → [Converting] → [Done]
```

State direpresentasikan sebagai flat `struct` + `enum`:

```swift
struct RecordingState {
    var status:       Status
    var elapsedSecs:  UInt32
    var selectedRect: CGRect
    var fps:          FrameRate

    enum Status:    UInt8 { case idle, selecting, recording, converting, done }
    enum FrameRate: UInt8 { case fps10 = 10, fps15 = 15, fps24 = 24 }
}
```

### 4.4 Memory Architecture: Temp File Pipeline

Untuk menjaga RAM usage minimal, pipeline menggunakan **temp file strategy**, bukan in-memory frame accumulation:

```
SCStreamOutput callback
    → Append frame ke FrameBuffer (flat SoA, pre-allocated)
    → Flush ke temp .mov di background actor setiap N frame
    → Saat Stop: finalize .mov → convert to .gif via ImageIO
    → Delete temp .mov
```

Ini memastikan RAM usage tetap rendah bahkan untuk rekaman panjang.

### 4.5 GIF Conversion Engine

Konversi menggunakan `ImageIO` dengan opsi:

| FPS | Use Case | Estimasi File Size (30 detik) |
|---|---|---|
| 10 FPS | UI demo singkat, ukuran minimal | ~2–4 MB |
| 15 FPS | **Default — sweet spot** README demo | ~4–8 MB |
| 24 FPS | Animasi halus, file lebih besar | ~8–15 MB |

> **Catatan:** 60 FPS dihilangkan. GIF format hanya support centisecond delay — 60 FPS tidak akurat secara spesifikasi dan menghasilkan file size yang tidak sebanding dengan peningkatan kualitas visual.

**Quality options:**
- Floyd-Steinberg dithering via `kCGImagePropertyGIFDictionary` — meningkatkan kualitas visual secara drastis tanpa menambah frame
- Frame dropping strategy saat lag: **drop frame, pertahankan timestamp** (bukan stretch delay) agar playback tidak "patah-patah"

### 4.6 Output Handler

Dua opsi output yang dapat dipilih di Preferences:
1. **Save to folder** — simpan ke Downloads / Desktop / custom path
2. **Copy to Clipboard** — otomatis copy file GIF ke system clipboard, siap di-paste

---

## 5. Permissions & Onboarding

`ScreenCaptureKit` memerlukan explicit user permission. Flow pertama kali buka app:

1. Tampilkan onboarding screen yang menjelaskan kebutuhan Screen Recording permission
2. Panggil `SCShareableContent.current` untuk trigger system permission dialog
3. Simpan permission state — jika ditolak, tampilkan panduan ke System Settings

Tambahan di `Info.plist`:
```xml
<key>NSScreenCaptureUsageDescription</key>
<string>GifBar memerlukan akses screen recording untuk merekam area layar yang dipilih.</string>
```

---

## 6. Keyboard Shortcuts

| Aksi | Shortcut (Default) |
|---|---|
| Trigger Record Area | `⌘⇧5` (customizable) |
| Start Recording | `Space` / `Return` saat overlay aktif |
| Stop Recording | `⌘⇧5` atau `Esc` |
| Cancel Selection | `Esc` saat overlay aktif |

Global shortcut didaftarkan via `NSEvent.addGlobalMonitorForEvents` agar aktif bahkan saat app tidak di-focus.

---

## 7. Non-Goals (Explicitly Out of Scope)

- Tidak ada video export (`.mp4`, `.mov`) — fokus GIF saja
- Tidak ada audio recording
- Tidak ada Mac App Store distribution (sandbox terlalu restrictive)
- Tidak ada 60 FPS option
- Tidak ada cloud upload / sharing integration
