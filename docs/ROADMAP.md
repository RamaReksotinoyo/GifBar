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

- [ ] `NSPanel` level `.floating`, resizable, semi-transparan
- [ ] Tampilkan dimensi real-time saat resize/drag
- [ ] `Esc` = cancel, kembali ke idle

**Bukti selesai:** klik "Record Area" → panel muncul di atas semua window, bisa di-resize, koordinat ter-log. Belum merekam.

---

## Iterasi 3 — State machine (§4.3)
**Tujuan:** lifecycle resmi sebelum menyentuh capture.

- [ ] `struct RecordingState` + `enum Status` sesuai §4.3
- [ ] `FrameRate` default `.fps15` (sinkronkan dengan §4.5)
- [ ] Transisi: `idle → selecting → recording → converting → done`

**Bukti selesai:** UI berubah sesuai status (Start/Stop muncul di state yang benar). Murni state, belum ada frame.

---

## Iterasi 4 — Capture pipeline inti (paling berat)
**Tujuan:** rekam area terpilih ke temp file.

- [ ] `SCStreamCoordinator` (satu-satunya `class`, delegate `SCStream`)
- [ ] `SCContentFilter` dari rect terpilih + `SCStreamConfiguration` (fps sesuai state)
- [ ] **KUNCI keputusan arsitektur** (resolusi inkonsistensi §3.3 vs §4.4):
  - **Opsi A (rekomendasi):** `CMSampleBuffer` → langsung `AVAssetWriter` ke temp `.mov`. RAM minimal, tanpa `pixelPool` Swift array.
  - **Opsi B:** akumulasi frame di FrameBuffer SoA in-memory.
  - Tidak bisa dua-duanya — §3.3 dan §4.4 saling meniadakan.

**Bukti selesai:** Start → Stop menghasilkan temp `.mov` valid & bisa diputar.

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
