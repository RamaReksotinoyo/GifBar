# Catatan Belajar: `SelectionOverlayController`

Penjelasan baris-per-baris file `GifBar/Selection/SelectionOverlayController.swift`
(Iterasi 2 — Selection overlay, SPEC §4.2), sekalian konsep Swift/AppKit yang muncul.

---

## Bagian A — `SelectionOverlayModel`

```swift
@Observable
@MainActor
final class SelectionOverlayModel {
    var size: CGSize = .zero
}
```

"Papan tulis kecil" berisi satu data: ukuran panel sekarang.

- **`@Observable`** → makro SwiftUI. Kalau `size` berubah, beri tahu siapa pun yang
  menampilkannya. Inilah yang bikin label "640 × 400" otomatis update tanpa panggil
  manual. View tinggal baca `model.size`, SwiftUI urus sisanya.
- **`@MainActor`** → semua akses ke kelas ini harus di main thread. UI wajib di main
  thread; ini jaminan dari compiler.
- **`final class`** → reference type yang tidak bisa di-subclass. Kenapa class, bukan
  struct? Karena `@Observable` butuh identitas stabil (di-share antara controller &
  view). Salah satu pengecualian "boleh reference type" di SPEC §3.

> Kenapa harus class terpisah, tidak langsung simpan `size` di controller? Karena View
> perlu "berlangganan" perubahan. Model adalah jembatan observasi antara controller
> (yang menulis) dan view (yang membaca).

---

## Bagian B — Properti controller

```swift
var onCommit: ((CGRect) -> Void)?
var onCancel: (() -> Void)?
```

Dua **closure opsional** = "callback". Controller tidak tahu (dan tidak peduli) apa
yang terjadi setelah user memilih area — dia cuma bilang "nih rect-nya" lewat
`onCommit`. Pemiliknya (nanti pipeline rekam) yang isi closure ini. Ini pola
**decoupling**: controller fokus urus panel, bukan urus rekam.

- `((CGRect) -> Void)?` = closure yang menerima `CGRect`, tidak mengembalikan apa-apa,
  dan **opsional** (`?` → boleh `nil` kalau tidak ada yang pasang).

```swift
private let model = SelectionOverlayModel()
private var panel: SelectionPanel?
private var resizeObserver: NSObjectProtocol?
private var keyMonitor: Any?
```

- `model` → `let` (dibuat sekali, tidak ganti).
- `panel`, `resizeObserver`, `keyMonitor` → `var` **opsional** (`?`), artinya **bisa
  kosong (`nil`)**. Saat panel belum tampil, ketiganya `nil`. Saat tampil, terisi. Saat
  ditutup, balik `nil`. Ini cara melacak "sedang tampil atau tidak".

---

## Bagian C — `present()`: memunculkan panel

```swift
if let panel {
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    return
}
```

**Guard pertama.** `if let panel` = "kalau `panel` tidak `nil` (sudah ada)". Maka jangan
bikin baru — cukup bawa yang lama ke depan, lalu `return` (keluar). Mencegah panel dobel
kalau "Record Area" diklik dua kali.

```swift
let screen = NSScreen.main ?? NSScreen.screens.first
let frame = centeredFrame(size: defaultSize, in: screen)
```

- `??` = **nil-coalescing**: "pakai `NSScreen.main`; kalau `nil`, pakai layar pertama."
- Hitung posisi awal: kotak `640×400` di tengah layar (helper `centeredFrame`).

```swift
let panel = SelectionPanel(
    contentRect: frame,
    styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
    ...
)
configure(panel)
```

Bikin panel dengan style yang tampak borderless tapi bisa resize. `configure(panel)`
mengeset properti detail (Bagian E).

```swift
let host = NSHostingView(rootView: SelectionOverlayView(model: model))
panel.contentView = host
```

**Jembatan SwiftUI ↔ AppKit.** Panel itu AppKit, isinya mau SwiftUI. `NSHostingView` =
bungkus View SwiftUI supaya bisa dipasang di window AppKit. Perhatikan `model` yang sama
dioper ke view → view & controller berbagi papan tulis yang sama.

```swift
model.size = frame.size      // set ukuran awal → label langsung benar
observeResize(of: panel)     // mulai dengarkan resize
installKeyMonitor()          // mulai dengarkan keyboard
NSApp.activate(ignoringOtherApps: true)
panel.makeKeyAndOrderFront(nil)   // tampilkan & jadikan fokus
self.panel = panel           // simpan referensi (sekarang tidak nil lagi)
```

---

## Bagian D — `dismiss()`: bersih-bersih

```swift
if let resizeObserver {
    NotificationCenter.default.removeObserver(resizeObserver)
}
resizeObserver = nil
if let keyMonitor {
    NSEvent.removeMonitor(keyMonitor)
}
keyMonitor = nil
panel?.orderOut(nil)
panel = nil
```

**Bagian KRUSIAL untuk performa/kebersihan.** Saat panel ditutup, kita **wajib melepas**
observer & key monitor. Kalau tidak:

- Observer terus hidup → kebocoran memori + bisa terpicu walau panel sudah hilang.
- Key monitor terus mencegat keyboard.

Setelah dilepas, semua di-`nil`-kan → kembali ke kondisi "tidak ada panel".
`panel?.orderOut(nil)` = sembunyikan jendela (`?` = "kalau panel ada").

> Inilah kenapa CPU balik ke 0 saat berhenti resize — observer dilepas dengan benar,
> tidak ada yang nyangkut.

---

## Bagian E — `configure()` & `centeredFrame()`

`configure` = daftar setelan panel: level mengambang, titlebar transparan, tombol
close/minimize/zoom disembunyikan, `minSize` (batas resize minimum — penegak hidup dari
aturan `SelectionGeometry.minimumSize`), `collectionBehavior` (boleh muncul di atas
fullscreen app, §4.2).

`centeredFrame` = matematika sederhana cari origin supaya kotak pas di tengah
`visibleFrame` (area layar di luar menu bar & Dock):

```text
x = tengah_layar_x − lebar/2
y = tengah_layar_y − tinggi/2
```

---

## Bagian F — `observeResize()`: label live

```swift
resizeObserver = NotificationCenter.default.addObserver(
    forName: NSWindow.didResizeNotification,
    object: panel,
    queue: .main
) { [weak self] _ in
    MainActor.assumeIsolated {
        self?.model.size = panel.frame.size
    }
}
```

- **`NotificationCenter`** = sistem "pengumuman" macOS. Kita daftar: "setiap kali panel
  ini di-resize (`didResizeNotification`), jalankan blok ini."
- Isinya: update `model.size` → karena `@Observable`, label di view ikut berubah.
  Mekanisme **dimensi real-time**.
- **`[weak self]`** → penting! Mencegah **retain cycle**. Tanpa `weak`, closure memegang
  controller kuat-kuat, controller memegang observer, observer memegang closure →
  lingkaran yang tidak pernah dibebaskan = kebocoran memori. `weak` memutus lingkaran
  itu. `self?` = "kalau controller masih ada, lakukan."
- `MainActor.assumeIsolated { }` = penegasan ke compiler bahwa blok ini jalan di main
  thread (karena `queue: .main`), supaya boleh menyentuh `model` yang `@MainActor`.

---

## Bagian G — `installKeyMonitor()`: keyboard

```swift
keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    guard let self else { return event }
    switch event.keyCode {
    case 53:            self.cancel(); return nil   // Esc
    case 36, 76, 49:    self.commit(); return nil   // Return, keypad Enter, Space
    default:            return event
    }
}
```

- **Local monitor** = intip setiap tombol yang ditekan **selama app kita aktif**. (Beda
  dengan *global* monitor di Iterasi 7 yang menangkap walau app tidak fokus.)
- `event.keyCode` = kode tombol. `53` = Esc, `36` = Return, dst. (Angka mentah ini kurang
  enak dibaca — kandidat dirapikan jadi konstanta bernama nanti.)
- **Nilai balik penting:**
  - `return nil` = "tombol ini **sudah kutangani**, jangan teruskan ke sistem" (mencegah
    bunyi *beep* / aksi lain).
  - `return event` = "bukan urusanku, teruskan seperti biasa."
- `guard let self else { return event }` = kalau controller sudah dibebaskan, biarkan
  event lewat.

---

## Bagian H — `commit()` & `cancel()`: aksi akhir

`commit()` (user menekan Return/Space):

```swift
guard let panel else { return }
let primaryHeight = NSScreen.screens.first?.frame.height ?? panel.frame.maxY
let captureRect = SelectionGeometry.captureRect(
    fromAppKitFrame: panel.frame, primaryScreenHeight: primaryHeight
)
print(...)             // sementara: log
onCommit?(captureRect) // beri tahu pemilik
dismiss()              // tutup & bersih-bersih
```

Di sinilah `SelectionGeometry.captureRect` dipakai: terjemah koordinat panel → koordinat
kamera, lalu serahkan via `onCommit`. `print` itu placeholder Iterasi 2; Iterasi 4 nanti
ganti dengan "kirim ke pipeline rekam".

`cancel()` (user menekan Esc): cukup log, panggil `onCancel`, tutup.

---

## Gambaran besar

```text
present()  ──► bikin panel + view + pasang "telinga" (resize & keyboard)
                  │
   resize ────────┼──► observeResize → update model → label berubah
   Esc    ────────┼──► cancel()  ─┐
   Return ────────┼──► commit()  ─┤──► dismiss() (lepas telinga, tutup)
                  │                │
            onCommit/onCancel ─────┘ kabari pemilik
```

Tiga konsep terpenting dari file ini:

1. **Optionals (`?`, `if let`, `??`)** untuk melacak "ada/tidak ada panel".
2. **`[weak self]`** untuk mencegah retain cycle (kebocoran memori).
3. **Lepas observer di `dismiss()`** — alasan kenapa CPU sehat balik ke 0.
