# PLAN-001 — Fase A: Stabilisasi Inti

- **Status:** Selesai — gerbang device terbukti via log user iPhone 17 (LogExpense mulai→parse sukses→konfirmasi; keyboard & QuickAdd dipakai). Catatan pasca-gerbang: tombol "Selesai" dihapus atas preferensi user (tap/scroll dismiss cukup).
- **Dibuat:** 2026-07-04 · **Selesai:** 2026-07-06
- **Induk:** PLAN-000-master-roadmap
- **Commit range:** `1336222`(A0) `3234cd0`(A1) `a4eea46`(A2) `87b47a6`(A4) `f5ead39`(A3) `846de8e`(A5)

## Hasil eksekusi
- A0 ✅ plan docs + signpost + DEBUGGING.md.
- A1 ✅ keyboard: scroll/tap/Selesai dismiss (gated agar fokus field tak regresi); terverifikasi sim.
- A2 ✅ AppContainer.shared sekali per proses; QuickLogPipeline timeout 15s + error granular (4 test).
- A3 ✅ snippet konfirmasi interaktif + Edit di App (PendingDraftStore 2 slot, handoff → TransactionFormView).
- A4 ✅ parser: few-shot salah diperbaiki, glossary, greedy; eval live 20 kalimat: amount 100%, type 100%, kategori 88% (2 miss subkategori Olahraga — batas model 300M, layar konfirmasi menutupi).
- A5 ✅ TransactionFormView tunggal (add/edit/confirmDraft); CRUD sim end-to-end ✅.
- Total 25 unit test hijau (incl. live eval di Mac host).

Tujuan: tutup 3 bug device (iPhone 17); parser terukur; intent tahan banting. Kerjakan berurutan; commit per langkah; `swift test` + `xcodebuild build` hijau tiap commit.

## Bug (dari testing user)

- **BUG-1a parser output salah.** TERKONFIRMASI: few-shot salah di `FoundationModelsParser.instructions` (`"5.73m" -> 5370000`, benar 5 730 000). Nama kategori Indonesia + input English tanpa glossary. Tanpa kontrol determinisme/eval.
- **BUG-1b konfirmasi tak bisa diedit.** `requestConfirmation(dialog:)` biner. Gap desain, bukan bug. Adopsi `SnippetIntent`/`requestConfirmation(snippetIntent:)` (swiftinterface ±4340).
- **BUG-2 intent stuck lalu error.** Hipotesis peringkat: (a) `AppContainer.make()` per invocation → CloudKit init+seed+dedupe tiap kali, potensi 2 proses buka store; (b) durasi inference > budget App Intent; (c) kerja berat di `@MainActor perform()`; (d) `fatalError` fallback di proses headless.
- **BUG-3 keyboard tak bisa dismiss.** `Form` tanpa `.scrollDismissesKeyboard` + tanpa toolbar Done.

## Langkah

**A0. Handoff & diagnosa.** Docs plan bernomor (PLAN-000/001/002) + logging rapi + `Docs/DEBUGGING.md`. Logging: subsystem `com.aban.My-RezekiKu`, kategori `Parser`/`Persistence`/`Intent`; `OSSignposter` durasi parse & commit. DEBUGGING.md: cara ambil log device (Console.app filter subsystem, `log collect --device`).

**A1. BUG-3 keyboard.** `.scrollDismissesKeyboard(.immediately)` + `ToolbarItemGroup(placement: .keyboard)` "Selesai", pada `QuickAddView`, `ConfirmDraftView`, `AddEditTransactionView`. Verifikasi simulator (computer-use) + screenshot.

**A2. BUG-2 intent hardening.**
- `AppContainer`: cache `static let shared` (sekali per proses); seed+dedupe hanya pertama.
- Ekstrak `QuickLogPipeline` testable: `run(text:) async throws -> TransactionDraft` + error granular (model unavailable / parse gagal / simpan gagal) → dialog spesifik.
- Timeout guard (`withThrowingTaskGroup`, ~15s) → dialog ramah bukan stuck.
- Kerja non-UI keluar MainActor bila aman (repository tetap MainActor).
- Signpost; catat p50/p95 di DEBUGGING.md (device).

**A3. BUG-1b konfirmasi bisa diedit (riset dulu).** Riset SDK swiftinterface + Apple/HWS: `SnippetIntent` + `requestConfirmation(snippetIntent:)`. Snippet ringkasan draft (nominal/kategori/merchant/tanggal), aksi Simpan / Edit di App / batal. "Edit di App": simpan `TransactionDraft` (Codable) ke app container + buka app → deteksi pending draft saat aktif → `ConfirmDraftView` prefilled → commit `source: .appIntent`. Fallback bila snippet tak memadai: biner + jalur "Edit di App". Dokumentasikan keputusan.

**A4. BUG-1a parser terukur.** Perbaiki few-shot salah; tulis ulang instruksi + glossary kategori (`Tagihan (bills/utilities)`, `Gaji (salary)`, dst). Cek `GenerationOptions` (sampling/temperature) → konservatif. Eval harness `Tests/ServicesTests/ParserLiveEvalTests.swift`: ≥20 kalimat English + expected, `.enabled(if: SystemLanguageModel available)`. Target ≥90% akurasi amount/type; lapor di commit. Error QuickAdd → pola alert.

**A5. Konsolidasi form.** `AddEditTransactionView` + `ConfirmDraftView` → `TransactionFormView` (mode add/edit/confirm) di `Features/Transactions/`; ConfirmDraft jadi wrapper tipis. Hanya jika test+build hijau; jika berisiko, tunda + catat.

**A6. Gerbang (WAJIB sebelum Fase B).**
- Unit: semua suite + eval lokal.
- Simulator: keyboard dismiss, QuickAdd graceful, CRUD regresi (screenshot).
- Device iPhone 17 (user, checklist): (1) QuickAdd English → draft benar → edit → simpan; (2) intent Siri happy path; (3) intent ambigu → error ramah; (4) konfirmasi snippet simpan/edit-di-app/batal; (5) keyboard dismiss. Semua ✅ = Fase A selesai → update PLAN-002 Status Aktif.
