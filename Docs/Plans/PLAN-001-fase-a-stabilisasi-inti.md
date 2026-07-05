# PLAN-001 — Fase A: Stabilisasi Inti

- **Status:** Aktif
- **Dibuat:** 2026-07-04
- **Induk:** PLAN-000-master-roadmap
- **Commit range:** mulai setelah `1c77517`

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
