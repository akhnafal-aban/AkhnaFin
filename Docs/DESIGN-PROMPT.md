# My RezekiKu — Design System Base Prompt (untuk Claude Design)

> Instruksi: Berikan penyesuaian untuk design prompt berikut untuk mengikuti style design referensi. Selain dari UI, tekankan juga prompt di bagian UX dengan menu mengikuti gambar yang terdapat referensi Menu
> context, tambahkan permintaan spesifik di bagian **[REQUEST]** paling bawah.
> Bagian bertanda `[PILIH: …]` diisi sesuai referensi yang dikirim.

---

You are designing for **My RezekiKu**, a personal finance capture app for iOS, built natively in SwiftUI. Follow this design system strictly and consistently across every screen you produce.

## Product identity
- Core promise: **frictionless expense capture** — logging a transaction takes one sentence or one screenshot. The app exists because manual expense tracking feels like a chore.
- Two hero flows (already shipped; the design must keep them front and center):
  1. **Quick Add** — user types one short English sentence ("buy meatballs 20k at the office canteen") → AI fills a draft → user confirms.
  2. **Receipt Shortcut** — user screenshots a receipt → triggered via Shortcuts/Action Button → a confirmation card appears OUTSIDE the app (Siri snippet) → saved with the receipt image attached.
- Sacred rule: **every AI result passes an editable confirmation before saving.** Never design an auto-commit flow.
- Solo personal app, not a fintech product: warm, quick, zero bureaucracy. No login screens, no onboarding walls — usable within 5 seconds of first launch.

## Platform & constraints
- iOS 26 **Liquid Glass** design language. SwiftUI-native components only: `List`/`Form` inset-grouped, `TabView` (floating glass tab bar), sheets with grabber, `ContentUnavailableView` for empty states, swipe actions, `.searchable` bar, segmented pickers, menu pickers.
- Everything must be implementable without custom drawing: system materials, SF Symbols only (no custom icon set), standard navigation patterns, Dynamic Type friendly, full light & dark mode.
- UI copy language: **Bahasa Indonesia**, singkat dan hangat (existing copy: "Catat Cepat", "Belum ada transaksi", "Tap + untuk mencatat transaksi pertamamu.", "Dari kalimatmu", "Konfirmasi Transaksi", "Simpan/Batal").
- Currency: Indonesian Rupiah, formatted **"Rp25.000"** — thousands dots, no decimals, no space after "Rp". Amounts always use **monospaced digits**.

## Foundations
- **Typography:** SF Pro (system). Large Title on tab roots; `.title2.bold()` for hero amounts; `.callout`/`.subheadline` for detail rows; `.caption` secondary metadata.
- **Color:** system background hierarchy (grouped background + glass bars). Accent color: [PILIH: iOS default blue / custom brand hue]. Semantic: income amounts = system green with "+" prefix; expense = primary label; destructive = system red.
- **Category palette (fixed seed categories, use as icon-circle tints & chart colors):**
  - Main Food `#F97316` (fork.knife) · Lifestyle `#8B5CF6` (sparkles) — sub: Jajan (takeoutbag.and.cup.and.straw), Hiburan (gamecontroller), Olahraga (figure.run) · Tagihan `#EF4444` (doc.text) · Transport `#3B82F6` (car) · Kesehatan `#10B981` (cross.case) · Gaji `#22C55E` (banknote) · Bonus `#EAB308` (gift)
- **Shape & spacing:** iOS 26 default continuous corner radii; 4pt spacing grid; comfortable one-hand reach — primary actions in lower half or trailing toolbar.

## Existing components (designs must map 1:1 — don't invent replacements)
- **TransactionRow:** leading 32pt circular icon (category SF Symbol on quaternary fill), title = merchant → note → category fallback, caption subtitle "Kategori • NamaTempat", trailing amount (green + prefix for income).
- **TransactionFormView** (one form, 3 modes: add / edit / confirm-draft): segmented "Pengeluaran | Pemasukan | Transfer", section Nominal (IDR field), section Detail (kategori menu dengan subkategori "Lifestyle › Jajan", tanggal, merchant, catatan), toolbar Batal/Simpan (Simpan disabled saat nominal 0). Confirm mode menambah banner kutipan italic "Dari kalimatmu: “…”".
- **Confirmation Snippet (outside app):** compact card — hero amount besar, chip jenis transaksi, baris ikon+teks (kategori, merchant, catatan, tanggal), kutipan sumber, tombol bordered "Edit di App" full-width.
- **Quick Add screen:** satu multiline text field + contoh kalimat di footer + tombol "Buat Draft" (ikon wand.and.stars) + graceful state saat AI tidak tersedia.
- Keyboard selalu bisa ditutup (tap di mana pun / scroll).

## Screen inventory
1. **Transaksi** (root): search bar, section per hari ("Monday, 6 July"), rows, swipe Edit/Hapus, tombol +, empty state.
2. **Catat Cepat** (root): hero flow #1.
3. **Form/Konfirmasi** (sheet): dipakai 3 mode.
4. **Pengaturan** (root): saat ini placeholder (Versi, Penyimpanan iCloud) — boleh didesain penuh: kelola kategori, toggle lokasi, status sinkron.
5. **[Scope desain baru] Dashboard insight:** kartu tetap (bukan kustom): spending per kategori (donut/bar), tren waktu (line), income vs expense, total periode, top merchant — gunakan palet kategori di atas; gaya Swift Charts.

## Principles
- Speed over decoration: satu aksi primer per layar.
- Di layar konfirmasi, **nominal adalah hero** — terbaca dalam <1 detik.
- Empty state selalu mengajari aksi berikutnya, bukan sekadar ilustrasi.
- Jangan sembunyikan aksi destruktif; pertahankan pola swipe iOS.
- Hormati data asli: jangan mendesain field/data yang tidak ada di model (amount, type, date, note, merchant, kategori+sub, lokasi, gambar resi, rawInput).

## [REQUEST]
[Tulis permintaan spesifik di sini, mis.: "Design the Transaksi list and Dashboard screens, light & dark, iPhone 17 frame" / "Explore 3 visual directions for the confirmation card".]
