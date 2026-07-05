# PLAN-000 — Master Roadmap (PLAN V2: Stabilisasi Inti + Receipt Intent)

- **Status:** Aktif
- **Dibuat:** 2026-07-04
- **Commit dasar:** `1c77517` (HEAD saat plan dibuat)
- **Turunan:** PLAN-001-fase-a-stabilisasi-inti, PLAN-002-fase-b-receipt-intent

Konvensi dokumen plan (berlaku semua plan berikutnya):
- Direktori `Docs/Plans/`. Nama `PLAN-NNN-slug-kebab.md` (NNN 3 digit, urut kronologis).
- Header wajib: `Status: Draft|Aktif|Selesai|Batal`, tanggal, commit range, link plan induk.
- Satu task/fase besar = satu file. Update `Status` saat mulai/selesai. Jangan timpa plan lama — pengganti = nomor baru + link balik.

## 1. Konteks

**My RezekiKu** — app finansial iOS 26 pribadi (solo dev). Fase 0–2 selesai: fondasi modular + CRUD manual + NL parser (Foundation Models, input English) + App Intent Siri. User uji di **iPhone 17 fisik → 3 bug serius** pada fitur inti. Keputusan user:
1. Perbaiki total kualitas fitur inti sebelum fitur baru — maksimalkan testing & debugging.
2. Tambah skenario: screenshot resi via Shortcut → analisis → konfirmasi di luar app.
3. **Berhenti setelah 2 fase** (A & B). Fitur lain → backlog.
4. Setelah selesai: user minta template prompt design system untuk Claude Design (tunggu permintaan eksplisit).

## 2. Status Proyek (handoff)

Commit: `2d11ef8` fondasi → `6dc16b7` Fase 0 → `3e35255` refactor logic-only → `b7db52f` CLAUDE.md → `37df351` review fixes → `765f342` Fase 1 parser → `1c77517` Fase 2 intent.

**Arsitektur (final, jangan ubah tanpa persetujuan user):**
- App target = SEMUA UI + composition root: `App/` (My_RezekiKuApp, AppContainer, AppDependencies, RootView), `DesignSystem/`, `Features/Transactions/`, `Features/QuickAdd/`, `Intents/`.
- `Packages/RezekiKit` = logic only: `RezekiCore`, `ServiceInterfaces`, `Persistence`, `Services` (`import FoundationModels` HANYA di sini).
- Pipeline sakral: `input → TransactionParsing → TransactionDraft → konfirmasi user → TransactionRepository.commit()`.
- 19 unit test hijau.

**Gotchas (detail CLAUDE.md + memory):**
- Build/test WAJIB prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Foundation Models: tidak dukung Bahasa Indonesia → input English (final saat ini). Inference gagal di simulator (`ModelManagerError 1026`) → validasi live hanya iPhone 17 fisik.
- API tak pasti → verifikasi dari SDK swiftinterface (`.../iPhoneOS.sdk/.../<F>.framework/Modules/<F>.swiftmodule/arm64e-apple-ios.swiftinterface`).
- Simulator uji: iPhone 17 UDID `B0F77E13-3EC1-4674-9F99-AB1591D382A7` (runtime 26.3.1).

## 3. Review Fase 0→sekarang

**Sehat:** boundary modular compiler-enforced; model CloudKit-compliant + seeder idempotent/dedupe; pola konfirmasi-dulu konsisten; disiplin SDK-first + test-first + commit per slice.

**Bug device (prioritas 1):** lihat PLAN-001 §Bug.

**Utang teknis:** intent build container per invocation; duplikasi ConfirmDraftView↔AddEditTransactionView; logika intent tak testable; error QuickAdd tak konsisten.

## 4. Dua Fase

- **FASE A — Stabilisasi Inti** → PLAN-001 (Status Aktif). Tutup 3 bug device + parser terukur + intent tahan banting. Gerbang A6 wajib lulus (unit + sim + device user) sebelum Fase B.
- **FASE B — Receipt Screenshot via Shortcut** → PLAN-002 (Status Draft sampai A6 lulus). Vision OCR → parser resi → intent → konfirmasi di luar app → commit `source: .receipt` + `receiptImageData`.

## 5. Batas Scope — SETELAH FASE B: BERHENTI

Backlog diparkir (JANGAN kerjakan): Voice/Speech, batch entry UI, dashboard/Charts, SettingsFeature, LocationService impl, enhancement iOS 27, App Group widget. Arsitektur sudah sediakan protokol/hook.

**Next step (tunggu permintaan):** template prompt design system untuk Claude Design.

## 6. Cara Kerja

Skeptis + validasi Apple docs/HWS + SDK swiftinterface; slice kecil build+test hijau; commit per slice dgn alasan; jelaskan keputusan; hasil AI selalu lewat konfirmasi; UI internal di app, logic public di package.
