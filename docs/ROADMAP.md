# GifBar — Build Roadmap (Iterasi)

Roadmap pembangunan GifBar, dipecah menjadi 8 iterasi. Setiap iterasi
menghasilkan sesuatu yang **bisa dijalankan & dibuktikan** sebelum lanjut ke
iterasi berikutnya. Referensi pasal merujuk ke [`SPEC.md`](./SPEC.md).

Urutan ketergantungan: `0 → 1 → 2 → 3 → 4 → 5 → 6 → 7`.
Iterasi 4 adalah jantung aplikasi.

---

## Iterasi 0 — Fondasi proyek
**Tujuan:** app menjadi menu bar utility, bukan window biasa.

- [ ] Ganti `WindowGroup` → `MenuBarExtra` di `GifBarApp.swift`
- [ ] Set `LSUIElement = true` (Info.plist) → hilang dari Dock
- [ ] Set deployment target macOS 14.0
- [ ] Hapus `ContentView.swift` template, ganti menu: `Record Area`, `Preferences`, `Quit`

**Bukti selesai:** build jalan, ikon muncul di menu bar, tidak ada window/Dock icon, Quit berfungsi.

---

## Iterasi 1 — Permission & onboarding (§5)
**Tujuan:** dapat izin Screen Recording sebelum fitur apa pun.

- [x] Tambah `NSScreenCaptureUsageDescription` di Info.plist
- [x] Trigger dialog izin (pakai `CGRequestScreenCaptureAccess` — lebih bersih dari `SCShareableContent` untuk gerbang izin; SCK dipakai nanti di Iterasi 4)
- [x] Tentukan status izin; jika ditolak, tampilkan tombol "Open System Settings"
- [x] Cek izin secara lazy saat klik "Record Area" (opsi B)
- [x] Unit + integration tests (11 tests, semua lulus)

**Bukti selesai:** first launch memunculkan dialog izin macOS; setelah diizinkan, app tahu statusnya.

> ⚠️ Global shortcut (Iterasi 7) butuh **Accessibility permission** terpisah —
> dipisah ke iterasi sendiri agar tidak tercampur.

---

## Iterasi 2 — Selection overlay (§4.2)
**Tujuan:** user bisa pilih area layar `(X, Y, W, H)`.

- [x] `NSPanel` level `.floating`, resizable, semi-transparan (Pola A — panel = area; MVP)
- [x] Tampilkan dimensi real-time saat resize/drag (`@Observable` model + `didResizeNotification`)
- [x] `Esc` = cancel, kembali ke idle (Return/Space = commit, log rect)
- [x] Konversi koordinat AppKit↔capture (`SelectionGeometry`) + unit tests (9 tests)

**Bukti selesai:** build + `xcodebuild test` hijau (20 tests). Verifikasi visual panel butuh menjalankan app.

---

## Iterasi 3 — State machine (§4.3)
**Tujuan:** lifecycle resmi sebelum menyentuh capture.

- [x] `struct RecordingState` + `enum Status` sesuai §4.3 (`Sendable`, `Equatable`)
- [x] `FrameRate` default `.fps15` (benahi inkonsistensi §4.5)
- [x] Transisi via `Event` + reducer murni `apply(_:)` — transisi ilegal ditolak
- [x] `RecordingStore` (`@Observable`) + timer elapsed; menu reaktif terhadap status
- [x] Sambung `onCommit`/`onCancel` overlay → state machine
- [x] Unit tests transisi legal/ilegal, tick, reset, format elapsed (13 tests)

**Bukti selesai:** build + `xcodebuild test` hijau (33 tests). `recording`/`converting` masih placeholder (belum ada frame) sampai Iterasi 4.

---

## Iterasi 4 — Capture pipeline inti (paling berat)
**Tujuan:** rekam area terpilih ke temp file.

**KEPUTUSAN ARSITEKTUR (final): Opsi A** — `CMSampleBuffer` → langsung `AVAssetWriter` ke temp `.mov`. RAM minimal (§4.4). SoA/cache-locality §3.3 **tidak dipakai** (Opsi B butuh ratusan MB RAM). Dipecah jadi 4a (teruji) → 4b (capture nyata).

### 4a — Config + Writer (selesai)
- [x] `CaptureConfiguration` murni: `sourceRect` display-relative, dimensi piksel (even), frame interval, pilih display by overlap
- [x] `MovieWriter` bungkus `AVAssetWriter` → temp `.mov` (nonisolated, drop-frame on not-ready per §4.5)
- [x] Unit tests config-math + integration test MovieWriter pakai frame sintetis (11 tests)

### 4b — Capture nyata (belum)
- [ ] `SCStreamCoordinator` (satu-satunya `class`, delegate `SCStream`)
- [ ] `SCContentFilter` (display + exclude window app) + `SCStreamConfiguration` dari `CaptureConfiguration`
- [ ] Wire ke `RecordingStore`: `recording` → mulai capture; `stop` → finalize `.mov` → `conversionFinished`

**Bukti selesai (4a):** build + `xcodebuild test` hijau (44 tests). **Bukti 4b:** Start → Stop hasilkan temp `.mov` valid (verifikasi dengan menjalankan app).

---

## Iterasi 5 — GIF encoder (§4.5)
**Tujuan:** temp recording → `.gif`.

- [ ] `CGImageDestination` (UTType GIF), tulis frame + delay centisecond
- [ ] Floyd-Steinberg dithering via `kCGImagePropertyGIFDictionary`
- [ ] Frame-dropping saat lag: drop frame, pertahankan timestamp

**Bukti selesai:** `.gif` valid, loop, durasi & fps benar; ukuran file sebanding tabel §4.5.

> Cek di sini: rute `.mov → decode → GIF` lossy 2×. Pertimbangkan feed `CGImage`
> langsung dari capture; ukur perbedaannya.

---

## Iterasi 6 — Output handler (§4.6)
- [ ] Save to folder (Downloads/Desktop/custom)
- [ ] Copy to Clipboard (`NSPasteboard`)
- [ ] Pilihan output di Preferences

**Bukti selesai:** GIF tersimpan di lokasi pilihan, atau ter-paste ke app lain.

---

## Iterasi 7 — Shortcuts & polish (§6)
- [ ] Global shortcut `⌘⇧5` via `NSEvent.addGlobalMonitorForEvents` (+ Accessibility permission)
- [ ] `Space`/`Return` start, `Esc` cancel saat overlay aktif
- [ ] Preferences panel rapi + indikator elapsed time saat recording

**Bukti selesai:** shortcut jalan walau app tidak fokus; full flow end-to-end mulus.

---

## Catatan revisi SPEC (perlu dibereskan sambil jalan)
1. Klaim "View struct → cache-friendly" (§2/§3) keliru — alasan View struct bukan cache locality.
2. §3.3 (SoA `pixelPool`) bertabrakan dengan §4.4 (temp-file pipeline). Pilih satu di Iterasi 4.
3. `enum FrameRate` (§4.3) belum menandai default; §4.5 bilang 15 FPS default.
4. Onboarding (§5) hanya sebut Screen Recording; global shortcut butuh Accessibility juga.
