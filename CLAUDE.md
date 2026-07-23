# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyek

**AkhnaFin** — app finansial iOS pribadi (solo dev) yang menyelesaikan satu masalah: mencatat pengeluaran itu ribet, jadi tidak dilakukan. Solusinya: capture nyaris tanpa friksi lewat banyak jalur input (App Intent/Siri, natural language Indonesia/English, foto resi, batch entry) yang **semuanya bermuara ke satu pipeline**:

```
input (teks/suara/gambar) → TransactionParsing → TransactionDraft (editable)
    → konfirmasi user → TransactionRepository.commit() → SwiftData + CloudKit
```

Hasil AI **selalu** menjadi draft yang bisa diedit sebelum disimpan — jangan pernah commit langsung tanpa konfirmasi user.

**AI = routing per-peran (PLAN-007):** user memilih engine untuk parsing TEKS dan GAMBAR secara terpisah di Pengaturan → Model AI — `.appleLocal` (teks: Foundation Models on-device, English-only, gagal di sim; gambar: Vision OCR + ReceiptHeuristics, offline) atau `.openRouter(slug)` (model apa pun dari katalog publik `GET /api/v1/models`). `RoutingTransactionParser` resolve engine SAAT CALL dari `ModelPreferenceStore` (UserDefaults) — ganti setting langsung berlaku. Model OpenRouter non-structured → prompt-JSON + `extractJSONObject`; structured → `response_format json_schema strict` + `provider.require_parameters` (JANGAN set ini utk model tanpa `response_format` → "No endpoints found"). `reasoning.effort:"low"` default (terukur live: motong 23.2s → 7.9s). Default preferensi: `google/gemma-4-26b-a4b-it:free` kedua peran. API key OpenRouter di Keychain (`OpenRouterKeyStore`); tanpa key → graceful state. Personalisasi kategori = knowledge-graph mini `CategorySignal` — disuntik ke SEMUA engine.

## Commands

`xcode-select` di mesin ini menunjuk ke CommandLineTools yang **tidak punya plugin macro SwiftData** — semua build/test WAJIB diprefix `DEVELOPER_DIR`:

```bash
# Test package (cara tercepat memvalidasi logic — detik, tanpa simulator)
cd Packages/AkhnaFinKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Satu suite / satu test (Swift Testing)
... swift test --filter "PersistenceTests"
... swift test --filter "PersistenceTests/repositoryCRUD"

# Build app (simulator)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "AkhnaFin.xcodeproj" -scheme "AkhnaFin" \
  -destination 'generic/platform=iOS Simulator' build

# Jalankan di simulator (app path ada di DerivedData .../Debug-iphonesimulator/)
xcrun simctl boot <UDID> && xcrun simctl install <UDID> "<path>/AkhnaFin.app" \
  && xcrun simctl launch <UDID> com.aban.AkhnaFin
```

Urutan verifikasi setiap perubahan: `swift test` → `xcodebuild build` → launch simulator + screenshot → commit git per increment.

## Arsitektur (keputusan final — jangan diubah tanpa persetujuan user)

**Package = logic saja; UI = app target.** User secara eksplisit menolak UI di dalam package.

```
AkhnaFin/                 ← app target: SEMUA UI + composition root
  App/                       AkhnaFinApp (ModelContainer CloudKit→localOnly fallback,
                             seeding), AppDependencies (DI/wiring), RootView (TabView)
  DesignSystem/              komponen reusable (AmountField, CategoryPicker, TransactionRow)
  Features/<Nama>/           satu folder per fitur (Transactions/, nanti QuickAdd/, Voice/, …)
  Intents/                   (Fase 2) App Intents — wajib di app bundle

Packages/AkhnaFinKit/          ← local package: LOGIC ONLY, semua target punya .testTarget
  AkhnaFinCore                 @Model (MoneyTransaction, TransactionCategory, DebtRecord,
                             CategorySignal), enums, CurrencyFormatter, agregasi — tanpa dependensi
  ServiceInterfaces          TransactionDraft, CapturedPlace, protokol (TransactionParsing,
                             LocationCapturing, SpeechTranscribing, APIKeyStoring,
                             PersonalizationProviding) + mocks
  Persistence                ModelContainerFactory (.cloudKit/.localOnly/.inMemory),
                             CategorySeeder, TransactionRepository, DebtRepository,
                             SignalRepository
  Services                   implementasi konkret: OpenRouterClient/KeyStore/Parser,
                             QuickLogPipeline, CoreLocationService
```

Aturan boundary (di-enforce compiler, pertahankan):
- UI boleh bergantung ke logic; logic **tidak pernah** import SwiftUI/tahu soal UI.
- Feature UI memanggil service lewat **protokol `ServiceInterfaces`**, bukan implementasi konkret; `AppDependencies` yang me-wire. Transport AI/network provider (OpenRouter client) hanya boleh di target `Services`.
- API package `public` secara sengaja (akan dipakai extension targets: widget/App Intents/watch); view di app target `internal` — jangan tambah `public` di UI.
- Test & Preview pakai `ModelContainerFactory.make(mode: .inMemory)` + mock dari `ServiceInterfaces` — tanpa device/AI.

**MVVM hybrid** (validasi: Hacking with Swift "MVVM with SwiftData"): read reaktif via `@Query` langsung di View; logika bisnis via `@Observable` ViewModel/`@MainActor` service dengan `ModelContext`/repository **di-inject lewat init** (bukan dari environment). Jangan paksakan MVVM murni — `@Query` hanya hidup di View, itu by design.

## SwiftData + CloudKit (pelanggaran = crash saat init container)

Semua `@Model`: atribut optional **atau** punya default; relasi optional **dan** punya inverse; **tanpa** `@Attribute(.unique)`; enum harus `Codable`. Container: `iCloud.com.aban.AkhnaFin`. Sync hanya bisa diuji di device fisik yang login iCloud; inspeksi via CloudKit Console (environment Development).

## Penamaan — pelajaran nyata dari proyek ini

- Model bernama `MoneyTransaction`, **bukan** `Transaction` (bentrok `SwiftUI.Transaction` di semua file View).
- Kategori bernama `TransactionCategory`, **bukan** `Category` (bentrok typedef `Category` ObjC runtime saat dipakai lintas modul).
- Pola umum: hindari nama tipe yang sama dengan tipe framework Apple; cek bentrok dengan build lintas modul sebelum banyak file bergantung.

## Versi OS: baseline iOS 26, siap iOS 27

- Deployment target **26.0**. Semua fitur inti wajib jalan penuh dengan API iOS 26 (App Intents, SwiftData+CloudKit, Swift Charts, PhotosPicker; AI via OpenRouter — bukan on-device sejak PLAN-006).
- API iOS 27 = **progressive enhancement** di balik `if #available(iOS 27, *)`, terlokalisasi di satu tipe/target agar mudah diadopsi: sectioned fetch + `ResultsObserver` (Persistence), App Intents Testing framework, reorderable containers (Dashboard).
- **Swift 6 language mode** (strict concurrency) di package dan app; app target pakai `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## Cara kerja yang diminta user (penting)

1. **Selalu skeptis — termasuk terhadap instruksi user sendiri.** Sebelum mengikuti instruksi yang meragukan, validasi terhadap best practice; kalau bertentangan, sampaikan temuan + sumbernya, baru putuskan bersama.
2. **Jangan percaya pengetahuan lama.** iOS 27 & Xcode 27 dirilis setelah knowledge cutoff — untuk API/perilaku framework yang tidak 100% pasti, **cek dulu** dokumentasi resmi via web search sebelum menulis kode.
3. **Referensi yang diakui:** dokumentasi resmi Apple (developer.apple.com) sebagai sumber utama; hackingwithswift.com sebagai referensi best practice. Sumber lain boleh sebagai pelengkap, bukan dasar keputusan.
4. **Bertahap dan rapi.** Kerjakan dalam slice kecil yang selalu bisa di-build + di-test; satu commit git per slice dengan pesan menjelaskan alasan. User ingin memahami setiap langkah — jelaskan keputusan desain, jangan hanya menyodorkan hasil.

## Context-window per sesi (WAJIB)

Setiap sesi kerja, tulis snapshot konteks ke `Docs/context-window/NN-context-window.md`:
- **NN** = nomor urut 2 digit, increment dari file bernomor tertinggi yang sudah ada (sesi lalu `01` → sesi ini `02`, dst). **Satu file per sesi — jangan menimpa file sesi lama.**
- **Baca file sesi terakhir di awal sesi** untuk cepat paham keadaan proyek tanpa menggali ulang.
- **Isi wajib:** ringkasan sesi, keputusan & gotcha baru, commit range, status verifikasi tertunda (device/user), langkah selanjutnya.
- Tulis/perbarui di akhir sesi atau saat user memintanya. Tujuan: handoff mulus antar sesi (context window baru langsung nyambung).

## Roadmap fase (konteks arah)

Fase 0–2 ✅ (fondasi, NL parser, App Intents/Siri) → Fase 4 struk ✅ → Fase C dashboard + capture menu ✅ (PLAN-004) → hutang/piutang ✅ (PLAN-005) → **pivot AI ke OpenRouter ✅ (PLAN-006**: 2-stage Nemotron→gpt-oss, personalisasi CategorySignal**)** → sisa backlog: Voice (Fase 3), batch entry (Fase 5), notifikasi jatuh tempo, asset management (visi user). Tanpa heuristic fallback — graceful state bila key/model tak tersedia. Lokasi ditangkap otomatis-senyap saat commit (switch off di Settings). Kategori seed: Main Food; Lifestyle→(Jajan, Hiburan, Olahraga); Tagihan; Transport; Kesehatan; Gaji; Bonus.
