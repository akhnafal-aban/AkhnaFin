# PLAN-004 — Fase C: Dashboard + Restrukturisasi Jalur Capture

- **Status:** Selesai (verifikasi device oleh user tertunda)
- **Dibuat:** 2026-07-19
- **Commit range:** `904fc0d` (refactor intents) → lihat log fase C
- **Induk:** PLAN-000 (backlog dibuka kembali atas permintaan user)

## 1. Konteks

Fase A+B selesai; user membuka backlog dan memilih Dashboard (ranking #1 nilai
di catatan sesi 01: separuh visi awal, self-contained, verifiable di simulator).
Di tengah planning user menambah keputusan UX: tab "Catat Cepat" dihapus, semua
jalur capture dikonsolidasi ke menu "+" di Transaksi, plus jalur baru
**Upload Resi in-app** (galeri, bukan hanya Shortcut).

## 2. Scope

- **Dashboard (tab pertama):** segmen Minggu/Bulan/Tahun + panah antar periode;
  ringkasan keluar/masuk/selisih; donut kategori (top-5 + "Lainnya"); bar tren
  harian (bulanan untuk periode Tahun). Layout FIXED — reorderable container =
  enhancement iOS 27.
- **Menu "+" (HIG pull-down button):** Text Entry (sheet QuickAddView) →
  Upload Resi (PhotosPicker) → Manual. Urutan = prioritas pemakaian.
- **Hutang/piutang:** DIPARKIR → kandidat **PLAN-005**. Butuh domain modeling
  sendiri (counterparty, arah, status lunas, relasi pelunasan). Skema SwiftData
  additive aman CloudKit — dashboard tidak menghalangi; kartu "Hutang" tinggal
  ditambah nanti.

## 3. Keputusan teknis

| Keputusan | Alasan |
|---|---|
| Agregasi murni di `AkhnaFinCore` (`StatsPeriod`, `TransactionAggregation`) | Boundary: Swift Charts/PhotosUI hanya di app target; logic testable tanpa UI |
| Transfer dikecualikan dari totals | Perpindahan antar akun bukan arus keluar/masuk riil |
| Subkategori digulung ke induk di donut | Donut level teratas; detail per-sub = fase nanti |
| Periode Tahun pakai seri bulanan | 365 bar harian tidak terbaca (12 bar bulanan iya) |
| Ganti granularitas → snap ke periode berisi hari ini | Offset lintas granularitas tak bermakna |
| Filter periode in-memory di atas `@Query` | Pola `TransactionListView`; data personal-scale |
| Upload Resi pakai `QuickLogPipeline.parseReceiptDraft` yang sudah ada | Nol logic baru di package; error `QuickLogError` siap-tampil |
| `loadTransferable(type: Data.self)` bukan `Image` | `Image` hanya andal utk PNG; resi umumnya JPEG/HEIC |

## 4. Validasi HIG / docs resmi

- Menu "+" = HIG **pull-down button**: aksi kreasi terkait dikonsolidasi di satu
  tombol toolbar; label verba, prioritas tinggi di atas, tanpa submenu.
- Donut: 5–7 sektor max → top-5 + "Lainnya"; nilai positif saja (expense only).
- Sheet butuh affordance tutup → tombol "Tutup" di QuickAddView.
- `PhotosPicker` out-of-process → tanpa permission prompt.
- Aksesibilitas: `accessibilityLabel/Value` per mark chart (VoiceOver).

## 5. Perubahan per slice (satu commit per slice)

1. **Refactor intents (pra-fase):** dedup `confirmStashAndCommit`, snippet
   ramping, `displayName`, currencyCode, race fix RootView.
2. **Slice A:** `TransactionAggregation` + `StatsPeriod` + 10 test (TDD).
3. **Slice B:** hapus tab Catat Cepat; menu "+" 3 jalur; Upload Resi
   (PhotosPicker → OCR → konfirmasi + gambar); QuickAddView jadi sheet
   "Text Entry" + Tutup.
4. **Slice C:** `DashboardView` (Charts) + `monthlyExpenseSeries` + tab pertama.
5. **Seed demo DEBUG-only** (`AKHNAFIN_DEMO_SEED=1`) utk verifikasi visual sim.

## 6. Verifikasi

- 52 unit test hijau; `xcodebuild` SUCCEEDED (nol warning baru).
- Simulator iPhone 17: empty state ✓, dashboard terisi (ringkasan Rupiah, donut
  warna kategori + legend, tren) ✓ — screenshot di sesi.
- **Gotcha baru:** `simctl` juga wajib prefix `DEVELOPER_DIR` (tanpa itu daftar
  device kosong); env var ke app sim wajib prefix `SIMCTL_CHILD_`.
- **Tertunda (device user):** menu "+" tap-through, Upload Resi end-to-end
  (galeri → OCR → simpan + gambar), Text Entry live parse, snippet ramping +
  auto-close "Edit di App".

## 7. Berikutnya

- **PLAN-005 (kandidat):** hutang/piutang — model `Debt`/counterparty, status,
  relasi pelunasan; kartu Hutang di dashboard.
- Demo seed round-robin menempelkan kategori income ke expense (artefak seed,
  bukan bug agregasi) — rapikan bila seed dipakai lebih luas.
