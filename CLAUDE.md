# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proyek

**AkhnaFin** — app finansial iOS pribadi (solo dev) yang menyelesaikan satu masalah: mencatat pengeluaran itu ribet, jadi tidak dilakukan. Solusinya: capture nyaris tanpa friksi lewat banyak jalur input (App Intent/Siri, natural language via Foundation Models, suara via Speech, foto struk via Vision, batch entry) yang **semuanya bermuara ke satu pipeline**:

```
input (teks/suara/gambar) → TransactionParsing → TransactionDraft (editable)
    → konfirmasi user → TransactionRepository.commit() → SwiftData + CloudKit
```

Hasil AI **selalu** menjadi draft yang bisa diedit sebelum disimpan — jangan pernah commit langsung tanpa konfirmasi user.

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
  AkhnaFinCore                 @Model (MoneyTransaction, TransactionCategory), enums,
                             CurrencyFormatter, TransactionGrouping — tanpa dependensi
  ServiceInterfaces          TransactionDraft, CapturedPlace, protokol (TransactionParsing,
                             LocationCapturing, SpeechTranscribing, ReceiptScanning) + mocks
  Persistence                ModelContainerFactory (.cloudKit/.localOnly/.inMemory),
                             CategorySeeder, TransactionRepository
  Services                   (Fase 1+) implementasi konkret: FoundationModelsParser, dst.
```

Aturan boundary (di-enforce compiler, pertahankan):
- UI boleh bergantung ke logic; logic **tidak pernah** import SwiftUI/tahu soal UI.
- Feature UI memanggil service lewat **protokol `ServiceInterfaces`**, bukan implementasi konkret; `AppDependencies` yang me-wire. `import FoundationModels` (dan framework AI lain) hanya boleh di target `Services`.
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

- Deployment target **26.0**. Semua fitur inti wajib jalan penuh dengan API iOS 26 (Foundation Models, `SpeechAnalyzer`, Vision `RecognizeDocumentsRequest`, App Intents, SwiftData+CloudKit, Swift Charts).
- API iOS 27 = **progressive enhancement** di balik `if #available(iOS 27, *)`, terlokalisasi di satu tipe/target agar mudah diadopsi: sectioned fetch + `ResultsObserver` (Persistence), Foundation Models multimodal (Services/Receipt), `LanguageModel` protocol (swap provider), App Intents Testing framework, reorderable containers (Dashboard).
- **Swift 6 language mode** (strict concurrency) di package dan app; app target pakai `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## Cara kerja yang diminta user (penting)

1. **Selalu skeptis — termasuk terhadap instruksi user sendiri.** Sebelum mengikuti instruksi yang meragukan, validasi terhadap best practice; kalau bertentangan, sampaikan temuan + sumbernya, baru putuskan bersama.
2. **Jangan percaya pengetahuan lama.** iOS 27 & Xcode 27 dirilis setelah knowledge cutoff — untuk API/perilaku framework yang tidak 100% pasti, **cek dulu** dokumentasi resmi via web search sebelum menulis kode.
3. **Referensi yang diakui:** dokumentasi resmi Apple (developer.apple.com) sebagai sumber utama; hackingwithswift.com sebagai referensi best practice. Sumber lain boleh sebagai pelengkap, bukan dasar keputusan.
4. **Bertahap dan rapi.** Kerjakan dalam slice kecil yang selalu bisa di-build + di-test; satu commit git per slice dengan pesan menjelaskan alasan. User ingin memahami setiap langkah — jelaskan keputusan desain, jangan hanya menyodorkan hasil.

## Roadmap fase (konteks arah)

Fase 0 ✅ fondasi + CRUD manual → **Fase 1** NL parser (Foundation Models, `@Generable`, tanpa heuristic fallback — graceful state bila model unavailable) → Fase 2 App Intents/Siri → Fase 3 Voice → Fase 4 struk (Vision OCR → parser; multimodal saat iOS 27) → Fase 5 batch → Fase 6 dashboard (fixed, Swift Charts). Lokasi ditangkap otomatis-senyap saat commit (switch off di Settings). Kategori seed: Main Food; Lifestyle→(Jajan, Hiburan, Olahraga); Tagihan; Transport; Kesehatan; Gaji; Bonus.
