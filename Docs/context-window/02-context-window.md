# Context Window — Sesi 02

- **Tanggal:** 2026-07-19
- **Ringkasan:** Review + refactor Intents (dedup, snippet ramping, 3 fix
  correctness) → Fase C: dashboard Swift Charts + restrukturisasi jalur capture
  (tab Catat Cepat dihapus → menu "+" HIG pull-down + Upload Resi in-app baru)
  → PLAN-005 hutang/piutang (ledger terpisah, cicilan, kartu Dashboard) + fix
  crash Charts. 63 unit test hijau; verifikasi visual simulator lulus.
- **Commit range:** `904fc0d` (refactor intents) → `9af85c1` (fix donut) + docs.

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
| PLAN-005 hutang | `DebtRecord`/`DebtPayment`/`DebtDirection` (Core, CloudKit-compliant, status lunas DIHITUNG), `DebtRepository` (Persistence), UI `Features/Debts/` (list/form/detail, cicilan + Lunasi), kartu Hutang di Dashboard setelah Ringkasan (juga saat periode kosong), 11 test baru |
| Fix crash Charts | Donut `chartForegroundStyleScale(domain:range:)` fatal `ConcreteScale+Discrete.swift:96` → warna statis per SectorMark + `FlowLegend` manual (`9af85c1`) |

## Keputusan & gotchas baru (tambahan dari sesi 01)

- **`simctl` juga WAJIB prefix `DEVELOPER_DIR`** — tanpa itu `simctl list devices` KOSONG (jebakan senyap).
- **Env var ke app simulator wajib prefix `SIMCTL_CHILD_`** pada `simctl launch` (tanpa itu jadi launch argument, bukan env).
- `requestConfirmation` = member `AppIntent` → helper bersama harus extension `AppIntent`, bukan fungsi bebas.
- Transfer dikecualikan dari totals dashboard; subkategori digulung ke induk; periode Tahun pakai seri bulanan (365 bar tak terbaca).
- `loadTransferable(type: Data.self)` (bukan `Image`) untuk foto resi — JPEG/HEIC.
- Menu "+" = HIG pull-down button (aksi kreasi terkonsolidasi, label verba, prioritas atas). Sheet wajib punya tombol tutup.
- **PLAN-005 SELESAI** (bukan lagi kandidat): ledger terpisah dari kas (keputusan user), cicilan + paylater, Lunasi = payment sebesar sisa (idempotent), migrasi additive terverifikasi atas store lama.
- **JANGAN pakai `chartForegroundStyleScale(domain:range:)`** — fatal `Charts/ConcreteScale+Discrete.swift:96` (nil unwrap, data-dependent, sim iOS 26.x, ditemukan via bisect). Pakai warna statis per mark + legend manual.
- **Visi user tercatat (belum dibangun):** asset management — depresiasi, asset value, kategori aset. Tunggu permintaan eksplisit.
- **App Intents snippet — JANGAN `requestConfirmation(snippetIntent:)` untuk snippet dgn tombol aksi-sendiri** (mis. "Edit di App"): `await requestConfirmation` menahan `perform()`, tombol nested yang buka app TAK menutup snippet → nggantung (device-verified). Pakai RESULT snippet (`ShowsSnippetView`, perform selesai seketika) dgn tiap tombol = AppIntent yang commit/handoff/batal sendiri (WWDC25 sesi 275). Fix di `ca7bf0a`.

## PLAN-006 — Pivot AI ke OpenRouter (bagian akhir sesi)

- **Jalur Apple-native DIHAPUS** (FoundationModelsParser, VisionReceiptScanner, ReceiptHeuristics; `parseReceipt(text:)` → `parseReceipt(image:)`; ReceiptScanning mati). AI = `OpenRouterParser` 2-stage: Nemotron omni (`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`, teks Indonesia/English + foto resi) → `openai/gpt-oss-120b:free` (structured outputs strict + `provider.require_parameters`). Free tier = pilihan sadar user (privasi + rate limit tercatat di PLAN-006). Timeout pipeline 25s.
- **API key**: Keychain via `OpenRouterKeyStore` (`APIKeyStoring`), SecureField di Pengaturan; tak pernah di log/UserDefaults/ditampilkan ulang.
- **Personalisasi**: `CategorySignal` (@Model, edge berbobot merchant|keyword|bank → kategori) + `SignalRepository` (konfirmasi +1.0, edit +2.5, snippet ≤12 baris relevan ke prompt stage-2). Feedback loop: FormView confirmDraft + SaveDraftIntent merekam tiap commit jalur AI.
- **Gotcha test baru**: handler statis URLProtocol TIDAK boleh dibagi antar suite (suite jalan paralel → race) — satu subclass URLProtocol per suite.
- Bonus pivot: input Indonesia didukung; parser jalan di simulator; FM gotchas lama (unsupportedLanguageOrLocale, ModelManagerError 1026) kini historis.
- Commit: `f837149` A (transport) → `c8ca853` B (parser+hapus) → `3097e1d` C (signals) → `a7f3032` D (wiring+Settings).

## Status verifikasi tertunda (device / user)

- Menu "+" tap-through; Upload Resi end-to-end (galeri → OCR → simpan+gambar); Text Entry live parse (FM device-only); snippet ramping + auto-close "Edit di App" (inheren: `EditExpenseInAppIntent.openAppWhenRun` membatalkan `requestConfirmation`).
- Sync iCloud antar device (masih tertunda dari sesi 01).
- Label periode di device id_ID harus "Juli 2026" (sim English menampilkan "July 2026").

## Langkah selanjutnya

1. **User: paste API key OpenRouter di Pengaturan** (sim/device) → uji live Text Entry Indonesia, Upload Resi, snippet Siri, koreksi kategori 2× → lihat personalisasi bekerja.
2. Verifikasi device tertunda lainnya (snippet Simpan/Edit/Batal, sync CloudKit entity baru: Debt*, CategorySignal).
3. Backlog: Voice, batch, notifikasi jatuh tempo, asset management (visi), optimasi 1-call multimodal.
4. Rapikan seed demo (kategori income nempel ke expense — artefak seed).

## Peta dokumen

Sesi 01 → `01-context-window.md`. Plan aktif → `Docs/Plans/PLAN-004`. Knowledge graph → `graphify-out/graph.html` (526 node; `graphify query "<pertanyaan>"`).
