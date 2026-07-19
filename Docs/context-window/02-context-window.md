# Context Window — Sesi 02

- **Tanggal:** 2026-07-19
- **Ringkasan:** Review + refactor Intents (dedup, snippet ramping, 3 fix
  correctness) → Fase C: dashboard Swift Charts + restrukturisasi jalur capture
  (tab Catat Cepat dihapus → menu "+" HIG pull-down + Upload Resi in-app baru).
  52 unit test hijau; verifikasi visual simulator lulus.
- **Commit range:** `904fc0d` (refactor intents) → `b49ee5f` (seed demo) + commit docs sesudahnya.

## Yang selesai sesi ini

| Bagian | Ringkas |
|---|---|
| Review kode (level high) | 6 finding: snippet overcrowded, intent ~90% duplikat, label type hardcode, urutan `clearStash` sebelum commit, race `clearStash` di RootView, currencyCode hilang saat confirm |
| Refactor intents | `QuickLogConfirmation.confirmStashAndCommit` (extension `AppIntent` — `requestConfirmation` adalah member intent, bukan fungsi bebas); commit SEBELUM clear; snippet ramping (amount+jenis+1 deskriptor+tanggal); `TransactionType.displayName`; RootView clearStash hanya setelah edit-request dikonsumsi |
| Fase C Slice A | `StatsPeriod` (interval+step) + `TransactionAggregation` (totals tanpa transfer, roll-up subkategori, seri harian/bulanan zero-filled) — Core, TDD, 11 test |
| Fase C Slice B | Tab Catat Cepat DIHAPUS; toolbar "+" Transaksi = `Menu` (HIG pull-down): Text Entry → Upload Resi → Manual; Upload Resi = `PhotosPicker` → `Data` → `parseReceiptDraft` (pipeline resi yang sama dgn Shortcut) → konfirmasi + gambar; QuickAddView = sheet "Text Entry" + tombol Tutup |
| Fase C Slice C | `DashboardView` tab pertama: segmen periode + panah (maju disabled ke masa depan), ringkasan, donut `SectorMark` (top-5+"Lainnya", warna colorHex, `chartForegroundStyleScale`), bar tren (`unit: .day`/`.month`), a11y label per mark |
| Verifikasi sim | Empty state + dashboard terisi (screenshot). Seed demo DEBUG-only `AKHNAFIN_DEMO_SEED=1` |
| Docs | PLAN-004 (fase C, status Selesai), graphify graph di `graphify-out/` (gitignored) |

## Keputusan & gotchas baru (tambahan dari sesi 01)

- **`simctl` juga WAJIB prefix `DEVELOPER_DIR`** — tanpa itu `simctl list devices` KOSONG (jebakan senyap).
- **Env var ke app simulator wajib prefix `SIMCTL_CHILD_`** pada `simctl launch` (tanpa itu jadi launch argument, bukan env).
- `requestConfirmation` = member `AppIntent` → helper bersama harus extension `AppIntent`, bukan fungsi bebas.
- Transfer dikecualikan dari totals dashboard; subkategori digulung ke induk; periode Tahun pakai seri bulanan (365 bar tak terbaca).
- `loadTransferable(type: Data.self)` (bukan `Image`) untuk foto resi — JPEG/HEIC.
- Menu "+" = HIG pull-down button (aksi kreasi terkonsolidasi, label verba, prioritas atas). Sheet wajib punya tombol tutup.
- **Hutang/piutang = kandidat PLAN-005** (diminta user, diparkir sadar — butuh domain modeling counterparty/status/pelunasan; skema additive aman CloudKit).

## Status verifikasi tertunda (device / user)

- Menu "+" tap-through; Upload Resi end-to-end (galeri → OCR → simpan+gambar); Text Entry live parse (FM device-only); snippet ramping + auto-close "Edit di App" (inheren: `EditExpenseInAppIntent.openAppWhenRun` membatalkan `requestConfirmation`).
- Sync iCloud antar device (masih tertunda dari sesi 01).
- Label periode di device id_ID harus "Juli 2026" (sim English menampilkan "July 2026").

## Langkah selanjutnya

1. User verifikasi device (daftar di atas) → perbaiki temuan.
2. **PLAN-005 hutang/piutang** bila user lanjut.
3. Rapikan seed demo (kategori income nempel ke expense — artefak seed, bukan bug agregasi).

## Peta dokumen

Sesi 01 → `01-context-window.md`. Plan aktif → `Docs/Plans/PLAN-004`. Knowledge graph → `graphify-out/graph.html` (526 node; `graphify query "<pertanyaan>"`).
