# AkhnaFin — Ringkasan Sesi 01 (Teknis + Flow + Referensi Apple)

Dokumen ini merangkum keseluruhan progress sesi 01: dari nol → app fungsional
dengan 2 core feature capture + Settings, plus rename ke AkhnaFin. Fokus pada
**logika teknis**, **flow eksekusi**, dan **sitasi dokumentasi Apple** yang
mendasari tiap keputusan.

- **Commit range:** `2d11ef8` (fondasi) → `08cb3b8` (fix parser e-resi).
- **Status:** 39 unit test hijau; 2 fitur inti device-verified (kalimat + resi).
- **Naming:** AkhnaFin (ex "My RezekiKu"). Path disk masih `My RezekiKu/` di sebagian mesin; package `AkhnaFinKit`, modul `AkhnaFinCore`, bundle `com.aban.AkhnaFin`.

---

## 1. Arsitektur & pipeline

**Prinsip:** package = logic only, app target = semua UI + composition root.
Boundary di-enforce compiler (UI tak pernah dilihat oleh logic; feature memanggil
service lewat protokol `ServiceInterfaces`, wiring di `AppDependencies`).

```
Packages/AkhnaFinKit (logic)          AkhnaFin/ (UI + composition root)
  AkhnaFinCore    @Model, enums,        App/        AkhnaFinApp, AppContainer,
                  CurrencyFormatter,                 AppDependencies, RootView
                  TransactionGrouping    DesignSystem/  AmountField, CategoryPicker,
  ServiceInterfaces  TransactionDraft,                  TransactionRow, Color+Hex,
                  CapturedPlace, protokol             KeyboardDismiss
                  + mocks                Features/  Transactions/, QuickAdd/, Settings/
  Persistence     ModelContainerFactory, Intents/   LogExpenseIntent, LogReceiptIntent,
                  CategorySeeder,                    ConfirmExpenseSnippet, PendingDraftStore
                  TransactionRepository
  Services        FoundationModelsParser,
                  VisionReceiptScanner,
                  ReceiptHeuristics,
                  CoreLocationService,
                  QuickLogPipeline
```

**Pipeline sakral** (semua jalur capture bermuara ke sini):
```
input (teks/gambar) → TransactionParsing → TransactionDraft (editable)
    → konfirmasi user → TransactionRepository.commit() → SwiftData + CloudKit
```
Hasil AI TIDAK PERNAH tersimpan tanpa layar konfirmasi.

- **MVVM hybrid:** read reaktif via SwiftUI `@Query` di View; mutasi via
  `@MainActor` repository di-inject lewat init. Referensi pola: Hacking with
  Swift, "How to use MVVM to separate SwiftData from your views".
  → https://www.hackingwithswift.com/quick-start/swiftdata

---

## 2. Fase 0–2 — Fondasi, NL parser, App Intent

### 2.1 Data model (SwiftData + CloudKit)
`MoneyTransaction` & `TransactionCategory` (`@Model`). Aturan CloudKit dipatuhi:
tiap atribut optional/berdefault, relasi optional + inverse, tanpa
`@Attribute(.unique)`, enum `Codable`. Kategori subkategori = relasi
self-referential (`parent` / `subcategories`).
- SwiftData `@Model`: https://developer.apple.com/documentation/swiftdata/model()
- SwiftData + CloudKit via `ModelConfiguration(cloudKitDatabase:)`:
  https://developer.apple.com/documentation/swiftdata/modelconfiguration
- Batasan model untuk CloudKit (optional/default, inverse, no unique):
  https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
- **Penamaan:** `MoneyTransaction` bukan `Transaction` (bentrok
  `SwiftUI.Transaction`), `TransactionCategory` bukan `Category` (bentrok typedef
  `Category` ObjC runtime lintas modul).

### 2.2 NL parser — Foundation Models
`FoundationModelsParser` (di target `Services`, satu-satunya tempat
`import FoundationModels`). `@Generable ParsedTransaction` + `@Guide` per field;
`SystemLanguageModel.default.availability` untuk graceful state;
`session.respond(to:generating:options:)` dgn `GenerationOptions(sampling: .greedy)`
untuk determinisme. Mapper murni `ParsedTransaction.draft(...)` (unit-testable).
- Foundation Models overview: https://developer.apple.com/documentation/foundationmodels
- `SystemLanguageModel` / availability: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- `@Generable` guided generation: https://developer.apple.com/documentation/foundationmodels/generable
- `@Guide`: https://developer.apple.com/documentation/foundationmodels/guide
- `LanguageModelSession.respond`: https://developer.apple.com/documentation/foundationmodels/languagemodelsession
- `GenerationOptions` (sampling/temperature): https://developer.apple.com/documentation/foundationmodels/generationoptions

> **Temuan kunci (empiris):** on-device model iOS 26 mendukung 23 bahasa **tanpa
> Indonesia** (`SystemLanguageModel.default.supportedLanguages`). Input Indonesia
> → `GenerationError.unsupportedLanguageOrLocale`. Keputusan: input NL = **English**.
> Inference juga GAGAL di Simulator (`ModelManagerError 1026`) → parse live hanya
> di device fisik. Verifikasi API dari SDK swiftinterface, bukan pengetahuan lama.

### 2.3 App Intent / Siri — `LogExpenseIntent`
`AppIntent` dgn `@Parameter text`, `AppShortcutsProvider` (frasa +
`\(.applicationName)`). Konfirmasi INTERAKTIF via `SnippetIntent` +
`requestConfirmation(dialog:snippetIntent:)` — kartu ringkasan + tombol
`Button(intent:)` "Edit di App". Wajib di app bundle.
- App Intents overview: https://developer.apple.com/documentation/appintents
- `AppIntent`: https://developer.apple.com/documentation/appintents/appintent
- `AppShortcutsProvider`: https://developer.apple.com/documentation/appintents/appshortcutsprovider
- `SnippetIntent` (interactive snippets, iOS 26): https://developer.apple.com/documentation/appintents/snippetintent
- `requestConfirmation`: https://developer.apple.com/documentation/appintents/appintent/requestconfirmation(result:confirmationactionname:showprompt:)
- `Button(intent:)` di snippet: https://developer.apple.com/documentation/swiftui/button/init(intent:label:)

---

## 3. Fase A — Stabilisasi 3 bug device

Ditemukan user saat uji iPhone 17 fisik. Setiap fix diverifikasi.

**BUG-1a parser output salah** — akar: few-shot berisi matematika SALAH
(`5.73m -> 5370000`). Fix: perbaiki contoh + glossary kategori (nama Indonesia +
arti English) + greedy sampling. Eval harness `ParserLiveEvalTests` (korpus 20
kalimat, auto-skip bila Apple Intelligence tak ada): **amount 100%, type 100%**.

**BUG-1b konfirmasi tak bisa diedit** — `requestConfirmation(dialog:)` biner.
Fix: `SnippetIntent` interaktif (di atas) + handoff "Edit di App" (§3.1).

**BUG-2 intent stuck** — akar: `AppContainer` membangun ulang container CloudKit
tiap invocation. Fix: `static let shared` (sekali per proses) + `QuickLogPipeline`
dengan pagar waktu via `withThrowingTaskGroup` (parser lambat → `.timedOut`,
bukan hang) + mapping error granular.
- Swift Concurrency task group: https://developer.apple.com/documentation/swift/withthrowingtaskgroup(of:returning:body:)
- `Task.sleep(for:)`: https://developer.apple.com/documentation/swift/task/sleep(for:tolerance:clock:)

**BUG-3 keyboard tak bisa dismiss** — Fix: `.scrollDismissesKeyboard(.immediately)`
+ tap-anywhere (di-gate notifikasi `keyboardWillShow/Hide` agar fokus field tak
regresi). Tombol toolbar "Selesai" dihapus atas preferensi user.
- `scrollDismissesKeyboard`: https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)

### 3.1 Handoff "Edit di App" — `PendingDraftStore`
Dua slot file JSON di Application Support: "confirming" (untuk render snippet) &
"edit-request" (ditulis saat tombol Edit ditekan; dikonsumsi app saat
`scenePhase == .active`). Payload `Codable { draft, source }` (source eksplisit).
`EditExpenseInAppIntent` (`openAppWhenRun = true`) → promote slot → buka app.
- `scenePhase`: https://developer.apple.com/documentation/swiftui/scenephase

### 3.2 Konsolidasi form
`AddEditTransactionView` + `ConfirmDraftView` (duplikasi ~80%) → satu
`TransactionFormView` dgn `enum Mode { add, edit, confirmDraft }`.

---

## 4. Fase B — Receipt shortcut

**Flow:** user bayar → screenshot resi → Shortcut (Action Button/Back Tap) →
`LogReceiptIntent` (`@Parameter receipt: IntentFile`) → OCR → heuristik → snippet
konfirmasi A3 yang sama → `commit(source: .receipt, receiptImage:)`.

### 4.1 OCR — `VisionReceiptScanner`
Vision `RecognizeDocumentsRequest` (iOS 26) → `document.text.transcript` per
dokumen. Struktur dokumen lebih akurat untuk resi daripada OCR polos.
- Vision framework: https://developer.apple.com/documentation/vision
- `RecognizeDocumentsRequest` (iOS 26): https://developer.apple.com/documentation/vision/recognizedocumentsrequest
- `DocumentObservation`: https://developer.apple.com/documentation/vision/documentobservation
- (fallback) `RecognizeTextRequest`: https://developer.apple.com/documentation/vision/recognizetextrequest
- Param gambar App Intent `IntentFile`: https://developer.apple.com/documentation/appintents/intentfile

### 4.2 Parser resi — `ReceiptHeuristics` (deterministik, BUKAN LLM)
> **Kenapa bukan Foundation Models:** FM menolak SEMUA prompt yang MENGANDUNG
> teks Indonesia (bukan hanya bila diminta output Indonesia) — resi toko/e-wallet
> Indonesia pasti berisi kata Indonesia → jalur LLM mustahil. Heuristik justru
> lebih andal untuk domain sempit ini: deterministik, instan, jalan tanpa Apple
> Intelligence, 100% unit-testable.

Logika ekstraksi:
- **Total:** skor keyword `GRAND TOTAL(4) > TOTAL(3, negative-lookbehind subtotal)
  > JUMLAH=NOMINAL(2) > PEMBAYARAN=TAGIHAN(1)`; ambil kemunculan terakhir. Angka
  bisa sebaris ATAU di baris berikut (**e-receipt 2 kolom** dipisah OCR →
  `lookaheadAmount`). Fallback `headlineAmount`: nominal ber-prefix "Rp" pertama
  (mis. ShopeePay `-Rp87.800` tanpa label total). Exclude-list mencegah salah
  ambil `Biaya/Saldo/Promo/Poin/Cashback/Kembali`.
- **Angka format Indonesia:** titik ribuan `121.148`, koma desimal `30.000,50`,
  digit polos `25000`, prefix `Rp`, trailing `,-`.
- **Merchant:** label e-resi (`Ke/Bayar Ke/Penerima/Tujuan` → baris nama berikut;
  tolak deret ≥7 digit = no. rekening/PAN; `Dari/Sumber Dana` dikecualikan =
  pengirim). Fallback struk toko: baris atas + filter header (word-boundary).
- **Kategori:** keyword-map → kategori seed (mis. "sate" → Main Food).
- Resi selalu `type = .expense` (koreksi ke income di layar konfirmasi bila perlu).

**Uji:** korpus 5 e-resi nyata (transkrip OCR dari screenshot user: SeaBank,
ShopeePay, Livin' QRIS, Livin' transfer, Referral) — total+merchant benar.
Device-verified: SeaBank + Krom.

### 4.3 Pipeline & repository
`QuickLogPipeline.parseReceiptDraft(fromImage:)` = OCR + heuristik dgn pagar
waktu yang sama dgn jalur kalimat (`withTimeout` single-source).
`commit(_:source:place:receiptImage:)` — gambar disimpan ke
`@Attribute(.externalStorage)`.
- `@Attribute(.externalStorage)`: https://developer.apple.com/documentation/swiftdata/attribute(_:originalname:hashmodifier:)

---

## 5. Settings lengkap

**5.1 Status iCloud** — `AppContainer.activeStorageMode` (cloudKit/localOnly)
direkam saat container dibangun; ditampilkan di `SettingsView`.

**5.2 LocationService** — `CoreLocationService` (`LocationCapturing`): one-shot
`CLLocationManager.requestLocation()` + delegate dijembatani ke
`CheckedContinuation`, pagar waktu 5s, reverse-geocode `CLGeocoder`. TAK PERNAH
melempar (izin ditolak/timeout → nil, save tetap jalan). Auto-capture SENYAP saat
commit transaksi baru dalam-app, di-gate toggle `@AppStorage("recordLocation")`.
Info.plist `NSLocationWhenInUseUsageDescription`. Swift 6 strict-concurrency:
koordinat (Sendable) disalin sebelum hop `@MainActor`.
- CoreLocation: https://developer.apple.com/documentation/corelocation
- `CLLocationManager.requestLocation()`: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()
- `CLGeocoder.reverseGeocodeLocation`: https://developer.apple.com/documentation/corelocation/clgeocoder
- `requestWhenInUseAuthorization`: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()
- `CheckedContinuation` (bridge delegate→async): https://developer.apple.com/documentation/swift/checkedcontinuation
- Data sensitif lokasi (Info.plist): https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationwheninuseusagedescription

**5.3 Category CRUD** — `TransactionRepository.addCategory/updateCategory/
deleteCategory` (guard `isBuiltIn` tak bisa dihapus; hapus custom → transaksi &
subkategori ter-nullify via `deleteRule` model). UI `CategoryManagementView`
(list per jenis, induk+sub, swipe) + `CategoryEditView` (grid SF Symbol, swatch
warna) + helper `Color(hex:)`.
- SF Symbols: https://developer.apple.com/documentation/symbols
- SwiftData `@Relationship` deleteRule: https://developer.apple.com/documentation/swiftdata/relationship(_:deleteRule:minimummodelcount:maximummodelcount:originalname:inverse:hashmodifier:)

---

## 6. Rename → AkhnaFin
Direktori/target/scheme/bundle (`com.aban.AkhnaFin`), package `AkhnaFinKit`,
modul `AkhnaFinCore`, container CloudKit `iCloud.com.aban.AkhnaFin`, subsystem
`os.Logger`, docs. **Catatan rilis:** container CloudKit baru BELUM dibuat di
Apple Developer portal (container lama tak bisa direname) — wajib dibuat sebelum
rilis. PR: https://github.com/akhnafal-aban/My-RezekiKu/pull/1

---

## 7. Disiplin verifikasi (dipakai sepanjang sesi)
- Build/test CLI WAJIB prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  (xcode-select → CommandLineTools tanpa plugin macro SwiftData).
- API tak pasti → verifikasi dari SDK swiftinterface
  (`.../iPhoneOS.sdk/System/Library/Frameworks/<F>.framework/Modules/<F>.swiftmodule/arm64e-apple-ios.swiftinterface`).
  iOS 27 pasca knowledge-cutoff → jangan menebak.
- Slice kecil, satu commit per slice, `swift test` → `xcodebuild build` → sim
  screenshot/device sebelum lanjut.
- Sumber: dokumentasi resmi Apple (developer.apple.com) utama; hackingwithswift.com
  best practice.

## 8. Backlog (diparkir, urut nilai)
Dashboard (Swift Charts — separuh visi awal, verifiable di sim) → Voice
(SpeechAnalyzer/SpeechTranscriber, device-only) → Batch entry.
- Swift Charts: https://developer.apple.com/documentation/charts
- Speech (`SpeechAnalyzer`, iOS 26): https://developer.apple.com/documentation/speech/speechanalyzer

## 9. Peta dokumen
`Docs/Plans/PLAN-000..003`, `Docs/context-window/01-context-window.md`,
`Docs/DEBUGGING.md`, `Docs/SHORTCUT-RESI.md`, `Docs/DESIGN-PROMPT.md`, `CLAUDE.md`.
