# Shortcut: Catat Resi dari Screenshot

Skenario: selesai bayar → screenshot resi (e-wallet, struk kasir difoto, invoice) →
jalankan Shortcut → konfirmasi muncul **di luar app** → tersimpan + gambar resi ikut tercatat.

## Resep A — Screenshot langsung (utama)

Di app **Shortcuts** → `+` buat shortcut baru:

1. Tambah aksi **"Take Screenshot"** (kategori Media).
2. Tambah aksi **"Catat Resi"** (dari AkhnaFin). Parameter *Gambar Resi* otomatis
   terisi output Screenshot — bila tidak, tap parameternya → pilih variabel **Screenshot**.
3. Beri nama mis. **"Catat Resi"**, tambahkan ke Home Screen / Action Button /
   Back Tap (Settings → Accessibility → Touch → Back Tap) untuk akses satu-ketukan.

Alur saat dijalankan: layar di-screenshot → OCR + analisis (deterministik, cepat,
tidak butuh Apple Intelligence) → kartu konfirmasi berisi total/merchant/kategori →
**Simpan** / **Edit di App** / batal.

## Resep B — Dari foto yang sudah ada

1. Aksi **"Select Photos"** (atau "Get Latest Photos" limit 1).
2. Aksi **"Catat Resi"** dgn parameter = hasil langkah 1.

## Cara uji cepat

1. Buka resi contoh di layar (mis. struk e-wallet).
2. Jalankan shortcut Resep A.
3. Verifikasi kartu konfirmasi: total = nominal akhir (baris TOTAL), merchant benar.
4. **Simpan** → buka app → tab Transaksi: entri baru bersumber resi + gambar tersimpan.
5. Uji gagal: jalankan pada layar tanpa resi → pesan "Tidak menemukan nominal total…"
   (bukan stuck).

## Batasan & catatan

- Total diambil dari baris `TOTAL` / `GRAND TOTAL` / `JUMLAH` / `TAGIHAN` (Sub Total
  diabaikan). Resi tanpa baris total → error ramah; catat via Catat Cepat/manual.
- Tanggal transaksi di-set saat pencatatan (bukan tanggal cetak resi) — koreksi di
  layar konfirmasi bila perlu (tombol **Edit di App**).
- Bermasalah? Ambil log: lihat `Docs/DEBUGGING.md` (filter subsystem
  `com.aban.AkhnaFin`, kategori `Intent`/`Parser`).
