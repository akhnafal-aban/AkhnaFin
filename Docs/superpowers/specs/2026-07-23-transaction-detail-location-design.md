# Slice 1 — TransactionDetailView + verifikasi lokasi

**Tanggal:** 2026-07-23 · **Branch:** general/v1 · **Sesi:** 03

## Masalah

Tap transaksi di list langsung membuka `TransactionFormView(mode: .edit)` — tak
ada layar detail read-only. Akibatnya: (a) melanggar HIG (tap baris = lihat
detail, edit = aksi terpisah); (b) lokasi yang DITANGKAP & disimpan
(`latitude`/`longitude`/`placeName` di `MoneyTransaction`) TIDAK PERNAH
ditampilkan → user tak bisa verifikasi fitur lokasi bekerja; (c) gambar resi
juga tak terlihat setelah commit.

Lokasi sudah terbukti ditangkap benar di kode (`CoreLocationService`: one-shot,
izin WhenInUse, timeout 5s, reverse-geocode, tak pernah throw; Info.plist punya
`NSLocationWhenInUseUsageDescription`). Yang hilang murni lapisan tampilan.

## Solusi

File baru `AkhnaFin/Features/Transactions/TransactionDetailView.swift` (app
target, `internal`). Read-only, di-**push** dari baris list (bukan sheet).

### Navigasi (HIG)
- Tap baris → push `TransactionDetailView`.
- Edit → tombol toolbar "Edit" di detail → sheet `TransactionFormView(.edit)`
  (yang sudah ada, tak diubah).
- Swipe Edit/Hapus di list tetap dipertahankan.

### Isi (visual-first, teks minimal, SF Symbols; tanpa emoji)
- **Hero**: nominal besar `monospacedDigit`, warna per jenis; chip kategori
  (ikon + warna kategori).
- **Lokasi** (bila `latitude` & `longitude` non-nil): MapKit `Map` + `Marker`
  di koordinat, `placeName` sebagai caption. Section disembunyikan bila nihil.
- **Resi** (bila `receiptImageData` non-nil): gambar, tap perbesar.
- **Metadata** baris ikon: tanggal, merchant, catatan, badge sumber
  (manual/AI/resi/Siri), kalimat asli (bila dari AI).

### Boundary
- Tak menyentuh package (logic). Murni UI app target.
- MapKit iOS 26 (`Map`/`Marker`/`MapCameraPosition`) — API diverifikasi ke
  dokumentasi resmi Apple + skill `mapkit` saat implementasi.

## Verifikasi lokasi (2 arah)
1. **Display**: sisipkan lat/lng + placeName ke ≥1 transaksi demo-seed
   (`AKHNAFIN_DEMO_SEED=1`) → sim screenshot detail → peta render.
2. **Capture end-to-end**: simulate location di simulator + `LocationPreference`
   ON → add transaksi manual → buka detail → peta muncul.

## Testing
- Logic minim (view read-only) → verifikasi utama = build + sim screenshot.
- `swift test` tetap harus hijau (tak ada perubahan package).
- Urutan: build app → launch sim + screenshot detail (dengan & tanpa lokasi) →
  commit.

## Di luar scope (slice lain)
Snippet ramping (Slice 2), subkategori terlihat (Slice 3), dashboard redesign +
hero saldo net all-time (Slice 4).
