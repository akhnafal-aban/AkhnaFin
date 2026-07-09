# Debugging My RezekiKu

## Logging

Satu subsystem: `com.aban.My-RezekiKu`. Kategori:

| Kategori | Sumber | Isi |
|---|---|---|
| `Parser` | `Services/FoundationModelsParser`, `VisionReceiptScanner` | sukses/gagal parse, error FM verbatim, signpost `parse` (inference kalimat / heuristik resi) & `ocr` (Vision) |
| `Persistence` | `AppContainer`, `TransactionRepository` | fallback CloudKit→lokal, signpost `commit` |
| `Intent` | `Intents/` (Fase A2+) | tahapan intent, error granular |

## Ambil log dari device (iPhone 17)

**Live (Console.app):**
1. iPhone tersambung USB/Wi-Fi → buka Console.app → pilih device di sidebar.
2. Filter: `subsystem:com.aban.My-RezekiKu` (ketik di search, pilih "Subsystem").
3. Start streaming → reproduksi bug → pause → salin baris relevan.

**Retroaktif (sysdiagnose ringan):**
```bash
# arsip log device (butuh device tersambung + trust)
sudo log collect --device --last 15m --output ~/Desktop/rezekiku.logarchive
open ~/Desktop/rezekiku.logarchive   # buka di Console.app, filter subsystem sama
```

**Simulator:**
```bash
xcrun simctl spawn <UDID> log show --last 5m \
  --predicate 'subsystem == "com.aban.My-RezekiKu"' --style compact
```
UDID sim uji: `B0F77E13-3EC1-4674-9F99-AB1591D382A7`.

## Signpost (durasi parse/commit)

Instruments → template "os_signpost" → filter subsystem `com.aban.My-RezekiKu`. Interval `parse` (kategori Parser) = durasi inference FM; `commit` (Persistence) = durasi resolusi kategori + save. Catat p50/p95 hasil pengukuran device di sini:

| Tanggal | Interval | p50 | p95 | Catatan |
|---|---|---|---|---|
| _(isi saat A2/A6)_ | | | | |

## Reproduksi bug intent (BUG-2)

1. Pastikan app TIDAK di foreground (kill dari app switcher) — intent jalan headless.
2. Jalankan Shortcut/Siri "Log expense in My RezekiKu" dgn kalimat English.
3. Amati: stuck/error → segera `log collect --device --last 5m`.
4. Cari: kategori `Intent` tahapan terakhir sebelum diam; error FM di `Parser`; pesan `LaunchServices`/`runningboardd` soal terminasi (budget waktu).

## Gotchas

- Build/test CLI wajib `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- FM inference tidak jalan di simulator (`ModelManagerError 1026`) — uji live parse hanya di device.
- FM tidak dukung Bahasa Indonesia — input English. Lebih jauh: FM MENOLAK prompt
  yang MENGANDUNG teks Indonesia (`unsupportedLanguageOrLocale`) — karena itu parser
  RESI memakai heuristik deterministik (`ReceiptHeuristics`), bukan LLM, dan bekerja
  tanpa Apple Intelligence.
