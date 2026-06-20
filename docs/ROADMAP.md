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

### 4b — Capture nyata (kode selesai, verifikasi runtime pending)
- [x] `SCStreamCoordinator` (satu-satunya `class`/NSObject, delegate `SCStream`, `nonisolated`)
- [x] `SCContentFilter` (display + exclude app sendiri) + `SCStreamConfiguration` dari `CaptureConfiguration`
- [x] Hanya tulis frame `.complete`; drop-frame saat writer not-ready (§4.5)
- [x] Wire ke `RecordingStore`: `recording` → `coordinator.start`; `stop` → `coordinator.stop` → finalize `.mov` → `conversionFinished`; simpan `lastRecordingURL`
- [x] **Verifikasi runtime**: Record→Stop menghasilkan temp `.mov` valid (terbukti: rekaman 17,9s & 7,9s, dimensi benar, H.264; even-rounding 1033→1034 jalan; log bersih)

**Bukti:** build + `xcodebuild test` hijau (44 tests) + verifikasi runtime multi-monitor sukses. **Iterasi 4 SELESAI.**

---

## Iterasi 5 — GIF encoder (§4.5) — SELESAI
**Tujuan:** temp recording → `.gif`.

- [x] `GIFEncoder` murni (`nonisolated struct`): bungkus `CGImageDestination` (UTType GIF), streaming 1 frame/append, loop count 0, delay centisecond
- [x] `MovieToGIFConverter` (`nonisolated`): `AVAssetReader` decode 1 frame at a time → `CGImage` via `CIContext` → encoder (RAM datar, §4.4)
- [x] Frame-dropping saat fps target < sumber: drop frame, timeline maju per slot `1/fps` (bukan stretch delay)
- [x] Wire ke `RecordingStore.finishCapture()`: `.mov` → convert → simpan `.gif` ke `lastRecordingURL` → **hapus temp `.mov`** (§4.4). Gagal konversi → fallback ke `.mov`.
- [x] Unit tests `GIFEncoder` (frame count, loop, delay, rounding, empty) + integration `.mov→.gif` (valid, loop, dimensi, frame-drop, bad-file) — 9 tests

- [x] **Verifikasi runtime**: Record→Stop menghasilkan `.gif` valid (terbukti: 740×802 dari seleksi 739×802 — even-rounding jalan; 164 frame; loop=0 selamanya; temp `.mov` sesi terhapus)

**Bukti:** build + `xcodebuild test` hijau (53 tests) + verifikasi runtime sukses. **Iterasi 5 SELESAI.**

### Catatan implementasi (koreksi terhadap SPEC)
1. **`capacity` bukan "hint".** Argumen count di `CGImageDestinationCreateWithURL`
   adalah **kapasitas keras**: menambah frame melebihi angka itu membuat
   `finalize()` gagal. Converter menghitung batas-atas = `ceil(durasi × fps) + 2`.
2. **Dithering Floyd–Steinberg tidak punya key publik.** SPEC §4.5 bilang "via
   `kCGImagePropertyGIFDictionary`", tapi ImageIO **tidak** mengekspos toggle
   Floyd–Steinberg. Dithering terjadi **otomatis** saat ImageIO kuantisasi tiap
   frame ke palet 256 warna GIF. Jadi tujuan §4.5 tercapai lewat quantizer
   bawaan, bukan flag eksplisit. (Didokumentasikan di docstring `GIFEncoder`.)

> Belum diukur: ukuran file vs tabel §4.5 (butuh rekaman nyata). Rute
> `.mov → decode → GIF` lossy 2× — kandidat optimasi (feed `CGImage` langsung
> dari capture), **tidak** dikerjakan di MVP ini.

---

## Iterasi 6 — Output handler (§4.6)
**Tujuan:** GIF keluar dari tmp sandbox → tersimpan ke folder pilihan user.

**KEPUTUSAN (revisi SPEC §2): App Sandbox TETAP ON** demi peluang Mac App Store.
Folder bebas dipilih via `NSOpenPanel` + **security-scoped bookmark** (Rasa A:
pilih sekali → auto-save). Copy-to-Clipboard **ditunda ke Iterasi 7**.

- [x] `Preferences` struct (`Sendable`) + `PreferencesStore` (`@Observable`): simpan/resolve bookmark folder via `UserDefaults`; `revealInFinder`
- [x] `OutputHandler` (`nonisolated`): pindah GIF ke folder, nama berstempel waktu, buat folder bila perlu, hindari tabrakan nama
- [x] `ENABLE_USER_SELECTED_FILES` `readonly` → `readwrite`; sandbox tetap ON
- [x] Wire `RecordingStore`: sesudah konversi → save ke folder bookmark (start/stop security scope) → reveal di Finder
- [x] Menu "Choose Save Folder…" (`NSOpenPanel`) → simpan bookmark
- [x] Unit tests `OutputHandler` (move, nama, folder, tabrakan) + `Preferences` (round-trip `UserDefaults`) — 7 tests
- [ ] **Verifikasi runtime**: pilih folder → rekam → GIF muncul di folder & bisa dibuka

**Bukti:** build + `xcodebuild test` hijau (60 tests). Verifikasi runtime pending.

> **Catatan bug runtime (terpecahkan):** deinit class `@MainActor` (`PreferencesStore`)
> kena double-free libmalloc lewat shim back-deploy concurrency di deployment
> target 14.0 (crash saat `XCTMemoryChecker` dealloc objek tes). Diatasi dengan
> `nonisolated deinit {}`. Relevan juga untuk store `@MainActor` lain bila kelak
> di-dealloc dalam tes.

---

## Iterasi 7 — Shortcuts & polish (§6)
**Tujuan:** input keyboard (lokal + global), output clipboard, dan UI rapi.

Dipecah 4 sub-bagian. **Urutan kerja: 7a → 7b → 7d → 7c** (yang tanpa-izin &
risiko-rendah dulu; Carbon hotkey terakhir karena paling perlu verifikasi runtime).

> **KOREKSI SPEC §6:** global shortcut **tidak** memakai
> `NSEvent.addGlobalMonitorForEvents` — itu butuh **Accessibility permission** dan
> terbatas/diblokir di App Sandbox (keputusan Iterasi 6), tidak lolos App Store.
> Rute final: **Carbon `RegisterEventHotKey`** — resmi, sandbox-safe, tanpa izin
> tambahan, tetap zero-dependency (filosofi SPEC).

### 7a — Input lokal overlay (ringan, no permission) — kode selesai, verifikasi runtime pending
- [x] Petunjuk on-overlay di `SelectionOverlayView`: di bawah readout `W × H`,
      baris kecil & redup `⏎ / Space to start · Esc to cancel`
- [x] Bungkus readout+petunjuk jadi `VStack` dalam `RoundedRectangle(cornerRadius: 10)`
      (ganti `Capsule`, lebih pas untuk dua baris)
- [x] Sembunyikan baris petunjuk saat panel sempit (`width < 220`) agar tak kepotong —
      lewat fungsi murni `shouldShowHint(forWidth:)`
- [x] Wiring `Space`/`Return` → Start, `Esc` → cancel **sudah ada sejak Iterasi 2/3**
      (`installKeyMonitor` → `onCommit`/`onCancel`); dikonfirmasi tetap jalan
- [x] Unit test logika visibilitas petunjuk (4 tests)
- [x] **Verifikasi runtime**: buka overlay → petunjuk tampil; sempitkan → petunjuk hilang;
      Space/Return mulai rekam; Esc batal — **7a SELESAI**

### 7b — Copy-to-Clipboard (utang Iterasi 6, §4.6) — kode selesai, verifikasi runtime pending
- [x] `ClipboardWriter` (`@MainActor`): satu `NSPasteboardItem` dengan `.fileURL` +
      data GIF (`com.compuserve.gif`); pasteboard injectable untuk test
- [x] Tambah `copyToClipboard: Bool` di `Preferences` + setter (round-trip `UserDefaults`)
- [x] `RecordingStore.deliverOutput` jadi kombinasi independen: save-to-folder dan/atau
      clipboard; GIF tak pernah hilang (fallback temp)
- [x] Menu toggle "Copy to Clipboard" (sementara di menu; pindah ke panel di 7d)
- [x] Unit test `ClipboardWriter` (pakai `NSPasteboard(name:)` privat) + round-trip pref — 6 tests
- [x] **Verifikasi runtime**: toggle ON → rekam → paste ke Telegram → GIF **animasi** terkirim
      utuh (bukan PNG statis) — **7b SELESAI**

> **Catatan bug runtime (terpecahkan, 2 lapis):**
> 1. Clipboard dibaca **sesudah** GIF dipindah ke folder & scope ditutup → sandbox
>    tolak baca. Fix: baca byte dari temp **sebelum** dipindah.
> 2. File URL di clipboard menunjuk folder security-scoped tapi ditulis **setelah**
>    scope dilepas → `Sandbox extension … failed to obtain (-20)`, app penerima tak
>    bisa baca file → Telegram jatuh ke data-gambar → **PNG statis**. Fix: tulis
>    clipboard **di dalam blok scoped** agar file-URL flavor dapat sandbox extension
>    valid. File URL prioritas pertama → chat app ambil berkas `.gif` → animasi.

### 7d — Polish UI — kode selesai, verifikasi runtime pending
- [x] Indikator **elapsed time** di label menu bar (`MenuBarLabel`): idle → glyph `record.circle`;
      recording → `stop.circle.fill` + `elapsedDisplay`; converting → `circle.dotted`
- [x] **Preferences sebagai submenu** (gaya Amphetamine, hover-to-expand) — bukan window:
      fps picker (`.inline`, ✓), toggle Reveal in Finder, toggle Copy to Clipboard,
      Choose Save Folder…, info "Saved to: <folder>"
- [x] `fps` jadi preference tersimpan, disuntik ke state saat `.startRecording` (SPEC §4.5)
- [x] Item menu lepasan dipindah ke panel; toggle Copy-to-Clipboard tetap di menu untuk akses cepat;
      "Preferences…" pakai `SettingsLink`
- [x] Unit test round-trip `fps` (default 15, persist) — 2 tests
- [x] **Verifikasi runtime**: panel terbuka, fps picker jalan, elapsed time tampil & berjalan
      di menu bar — **7d SELESAI**

> **Catatan bug runtime (terpecahkan):**
> 1. **Window Preferences tak pernah muncul.** Di agent app (LSUIElement), scene
>    `Settings` + `SettingsLink`/`openSettings()`/`openWindow` dari `MenuBarExtra`
>    membuka nol yang terlihat. Sempat dicoba kelola `NSWindow` sendiri, lalu
>    **diputuskan ganti pendekatan**: Preferences jadi **submenu** (gaya
>    Amphetamine) — tak ada window sama sekali, jauh lebih sederhana & native.
>    `PreferencesWindowController`/`PreferencesView` dihapus.
>    > ⚠️ Window onboarding (Iterasi 1) masih memakai `openWindow` yang sama —
>    > berisiko kena bug serupa; perlu diverifikasi/dipindah ke AppKit nanti.
> 2. **Elapsed tak terlihat di menu bar.** `Label` di menu bar dirender ikon-saja
>    (judul disembunyikan). Fix: interpolasi glyph ke dalam `Text`
>    (`"\(Image(systemName:)) \(elapsedDisplay)"`).

### 7c — Global shortcut ⌘⇧5 (Carbon `RegisterEventHotKey`) — kode selesai, verifikasi runtime pending
**Revisi cakupan:** ⌘⇧5 = **stop-only** (bukan toggle). Start tetap via menu —
saat mulai rekam kamu memang sudah di app; nilai hotkey ada di **stop tanpa
memunculkan app** saat sedang merekam demo.
- [x] `HotKeyCenter` (satu `class`, pengecualian coordinator): daftar/lepas hotkey via Carbon;
      callback C threading `self` lewat `userData`; `nonisolated deinit` lepas hotkey + handler
- [x] ⌘⇧5 saat `recording` → `stopRecording` walau app tidak fokus; status lain diabaikan
- [x] Carbon `RegisterEventHotKey` → sandbox-safe, tanpa Accessibility (bukan `addGlobalMonitorForEvents`)
- [x] Esc-saat-recording & shortcut customizable **ditunda** (di luar MVP)
- [x] Unit test konstanta keycode (23 / `kVK_ANSI_5`) + modifier (`cmdKey|shiftKey`) — 2 tests
- [x] **Verifikasi runtime**: rekam dari menu → pindah ke app lain → tekan ⌘⇧5 → recording berhenti
      — **7c SELESAI**

**Bukti:** build + `xcodebuild test` hijau (75 tests) + verifikasi runtime sukses.
**Iterasi 7 SELESAI — seluruh roadmap (0→7) tuntas.** 🎉

**Bukti selesai:** overlay punya petunjuk & merespons Space/Return/Esc; GIF bisa
di-copy ke clipboard; Preferences panel rapi + elapsed time tampil; global ⌘⇧5
jalan walau app tidak fokus; full flow end-to-end mulus.

---

## Catatan revisi SPEC (perlu dibereskan sambil jalan)
1. Klaim "View struct → cache-friendly" (§2/§3) keliru — alasan View struct bukan cache locality.
2. §3.3 (SoA `pixelPool`) bertabrakan dengan §4.4 (temp-file pipeline). Pilih satu di Iterasi 4.
3. `enum FrameRate` (§4.3) belum menandai default; §4.5 bilang 15 FPS default.
4. Onboarding (§5) hanya sebut Screen Recording; global shortcut butuh Accessibility juga.



