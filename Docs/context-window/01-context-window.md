# Context Window — Sesi 01

- **Tanggal:** 2026-07 (sesi panjang: perencanaan awal → Settings)
- **Ringkasan:** Dari nol → app fungsional dengan 2 core feature shortcut (kalimat + resi) live, plus Settings lengkap; 36 unit test hijau.
- **Commit range:** `2d11ef8` (fondasi) → `2267b84` (S4 Settings).

## Proyek

**AkhnaFin** (sebelumnya "My RezekiKu" — **path folder di disk masih `My RezekiKu/`**, package `AkhnaFinKit`, bundle `com.aban.AkhnaFin`, container `iCloud.com.aban.AkhnaFin`). App finansial iOS 26 pribadi (solo dev). Masalah: mencatat pengeluaran ribet → tak dilakukan. Solusi: capture nyaris tanpa friksi lewat banyak jalur input, **semua bermuara ke satu pipeline sakral**:

```
input (teks/gambar) → TransactionParsing → TransactionDraft (editable)
    → konfirmasi user → TransactionRepository.commit() → SwiftData + CloudKit
```

Hasil AI **selalu** jadi draft yang dikonfirmasi user sebelum simpan.

## Yang selesai sesi ini

| Bagian | Ringkas | Ref |
|---|---|---|
| Fase 0 | Fondasi modular + CRUD manual; refactor **package = logic, UI = app target** | PLAN-000 |
| Fase 1 | NL parser Foundation Models (`@Generable`, greedy), **input English** | PLAN-000 |
| Fase 2 | App Intent/Siri `LogExpenseIntent` + snippet konfirmasi interaktif "Edit di App" (pola A3) | PLAN-000 |
| Fase A | Stabilisasi 3 bug device (parser salah, intent stuck, keyboard tak turun) + eval parser 100% amount/type + intent hardening (timeout, container sekali/proses) | PLAN-001 |
| Fase B | Receipt shortcut: `LogReceiptIntent` (gambar) → Vision OCR (`VisionReceiptScanner`) → **`ReceiptHeuristics` deterministik** → snippet A3 → commit `.receipt` + gambar | PLAN-002 |
| Review fixes | subsystem logger typo; regex nominal terima tanpa-pemisah/`,-`; race Edit-di-App (buang `clearStash` di jalur batal) | — |
| Settings | Kelola kategori (CRUD+sub, UI ikon/warna), toggle Rekam Lokasi + `CoreLocationService` (auto-capture senyap di commit dalam-app), status iCloud | PLAN-003 |

## Keputusan & gotchas kunci (WAJIB tahu di sesi baru)

- **Foundation Models TIDAK dukung Bahasa Indonesia** (23 bahasa, tanpa `id`) → input NL English. Lebih jauh: FM **menolak SEMUA prompt yang mengandung teks Indonesia** (`unsupportedLanguageOrLocale`, empiris, amplop English pun gagal) → **parser resi = heuristik deterministik**, bukan LLM (bonus: jalan tanpa Apple Intelligence).
- **FM inference GAGAL di simulator** (`ModelManagerError 1026`) → parse NL live **hanya di iPhone 17 fisik**. Simulator tetap berguna untuk UI/graceful-state/receipt-heuristik.
- **Build/test WAJIB** prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select → CLT tanpa macro SwiftData).
- **API tak pasti → verifikasi dari SDK swiftinterface** (`.../iPhoneOS.sdk/System/Library/Frameworks/<F>.framework/Modules/<F>.swiftmodule/arm64e-apple-ios.swiftinterface`). Jangan menebak dari pengetahuan lama (iOS 27 pasca-cutoff).
- **Penamaan:** `MoneyTransaction` (bukan `Transaction` — bentrok `SwiftUI.Transaction`), `TransactionCategory` (bukan `Category` — bentrok typedef ObjC).
- Simulator uji: iPhone 17 UDID `B0F77E13-3EC1-4674-9F99-AB1591D382A7` (runtime 26.3.x).

## Status verifikasi tertunda (device / user)

- Checklist device Fase A (QuickAdd/Siri/keyboard/snippet) & Fase B (screenshot resi → Shortcut → simpan+gambar) — sebagian sudah dikonfirmasi via log user.
- Cek visual layar Kelola Kategori (Mac terkunci saat sesi → nav UI belum dilihat; logic 36 test + build hijau).
- Sync iCloud antar device (butuh 2 device login Apple ID sama).

## Fase selanjutnya (backlog diparkir — jangan mulai tanpa diminta)

Urut nilai: **Dashboard** (Swift Charts — separuh visi awal, self-contained, verifiable di sim) → **Voice** (Speech, device-only) → **Batch entry**. Arsitektur sudah menyediakan protokol/hook (mis. `SpeechTranscribing`, `parseBatch`).

## Peta dokumen

- `Docs/Plans/PLAN-000..003` — roadmap + rincian per fase (status per file).
- `Docs/DEBUGGING.md` — cara ambil log device/sim, signpost, prosedur reproduksi bug.
- `Docs/SHORTCUT-RESI.md` — resep Shortcut untuk fitur resi.
- `Docs/DESIGN-PROMPT.md` — base prompt design system.
- `CLAUDE.md` — aturan proyek (arsitektur, gotchas, cara kerja, aturan context-window).
