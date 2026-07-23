# Context Window — Sesi 02

- **Tanggal:** 2026-07-19 → 2026-07-23 (sesi panjang, berlanjut lintas hari)
- **Ringkasan:** Review + refactor Intents → Fase C dashboard+capture menu →
  PLAN-005 hutang/piutang → **PLAN-006 pivot AI penuh ke OpenRouter** (2-stage
  lalu disederhanakan jadi 1-call) → **PLAN-007 user bisa pilih model AI
  sendiri per peran** (Apple lokal vs OpenRouter apa pun) → **PLAN-008 fix bug
  live + Text Entry bisa catat hutang**. Diselingi beberapa fix reaktif atas
  laporan device user (404 routing, decode gagal 3x varian). 92 unit test
  hijau; graphify graph diperbarui (1041 node).
- **Commit range:** `904fc0d` → `1fac01f` (HEAD) + docs. **Branch:
  `external-model/v1`, BUKAN main — belum di-merge.**

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

## PLAN-006 — Pivot AI ke OpenRouter (2-stage → lalu disederhanakan jadi 1-call)

- **Jalur Apple-native DIHAPUS total** (FoundationModelsParser, VisionReceiptScanner, ReceiptHeuristics; `parseReceipt(text:)` → `parseReceipt(image:)`; `ReceiptScanning` mati). AI = `OpenRouterParser` 2-stage awal: Nemotron omni (perception) → gpt-oss (generator).
- **API key**: Keychain via `OpenRouterKeyStore` (`APIKeyStoring`), SecureField di Pengaturan; tak pernah di log/UserDefaults/ditampilkan ulang.
- **Personalisasi**: `CategorySignal` (@Model, edge berbobot merchant|keyword|bank → kategori) + `SignalRepository` (konfirmasi +1.0, edit +2.5, snippet ≤12 baris relevan ke prompt). Feedback loop: FormView confirmDraft + SaveDraftIntent merekam tiap commit jalur AI. Tetap dipakai setelah collapse ke 1-call.
- **Gotcha test**: handler statis URLProtocol TIDAK boleh dibagi antar suite (suite jalan paralel → race) — satu subclass URLProtocol per suite. Berulang tiap file test baru (`RoutingMockURLProtocol`, `ParserMockURLProtocol`, dst).
- **Data live user memicu 3 putaran fix pasca-Slice awal:**
  1. 404 "No endpoints found" — Nemotron `:free` TAK dukung `response_format`; `gpt-oss-120b:free` slug **tidak ada** (cuma paid) → ganti `gpt-oss-20b:free`, `structured` jadi parameter opsional di client (`c02abef`).
  2. Timing terukur 23.2s (16.1+7.1) → `reasoning.effort:"low"` turunkan ke 7.9s (`ff4b2bb`). Instrumentasi timing per-stage ditambah duluan (`6c9383f`) supaya user bisa kasih angka nyata.
  3. **User minta lebih efisien lagi** → riset model gratis+multimodal via `GET /api/v1/models` (`supported_parameters`, uptime per-provider) → **collapse 2-stage jadi 1 call**, model tunggal `google/gemma-4-26b-a4b-it:free` (MoE, ~3.8B aktif/token, native structured outputs, 2 provider ~99% uptime) — kategori ikut ditebak di call yang sama, dibantu daftar kategori + `CategorySignal` (`b569349`).
- Bonus pivot: input Indonesia didukung; parser jalan di simulator; FM gotchas lama (unsupportedLanguageOrLocale, ModelManagerError 1026) kini historis.
- Commit inti: `f837149` A (transport) → `c8ca853` B (parser+hapus Apple) → `3097e1d` C (signals) → `a7f3032` D (wiring+Settings) → `c02abef`/`6c9383f`/`ff4b2bb` (3 fix reaktif) → `b569349` (collapse 1-call).

## PLAN-007 — User bebas pilih model AI sendiri per peran (Apple lokal ⇄ OpenRouter)

- Latar: meski sudah 1-call Gemma, user MASIH menilai kurang efisien/kontrol → minta kendali penuh: pilih engine untuk TEKS dan GAMBAR terpisah, termasuk balikin opsi Apple lokal.
- **Jalur Apple DIPULIHKAN dari `c8ca853^`** (FM + Vision OCR + heuristik — sempat dihapus PLAN-006) dibungkus `AppleTransactionParser`.
- `RoutingTransactionParser`: teks & gambar masing-masing `.appleLocal` atau `.openRouter(slug, supportsStructured, displayName)`; engine dibaca SAAT CALL dari `ModelPreferenceStore` (UserDefaults, bukan Keychain — bukan rahasia) — ganti setting di Pengaturan langsung berlaku, tanpa rebuild dependencies.
- `OpenRouterParser` diparameterisasi ulang: slug+structured per peran (bukan konstanta); model non-structured → prompt-JSON + `extractJSONObject` (di-restore, sempat dibuang saat collapse ke 1-call).
- Katalog: `OpenRouterModelCatalog` (actor, cache in-memory) — `GET /api/v1/models` PUBLIK tanpa API key, map image-capable/structured/harga/gratis.
- UI: Pengaturan → **Model AI** — per peran, pilih Apple (checkmark) atau OpenRouter → `ModelPickerView` (searchable, toggle "Hanya Gratis" default ON, filter image-capable otomatis utk peran gambar, badge JSON+harga, pull-to-refresh). Footnote jujur: Apple teks = English-only+Apple Intelligence; Apple gambar = OCR offline tanpa AI generatif.
- Commit: `3599c7c` A (restore Apple) → `0d81d7e` B (routing+preference) → `9a9b7c2` C (katalog+UI) → `0ac765f` D (docs). 83 test hijau di titik ini.

## PLAN-008 — Fix 404 (tangga fallback) + Text Entry bisa catat hutang

Dipicu 2 hal sekaligus dari user: (a) error live baru `HTTP 404 No endpoints found` muncul LAGI setelah user ganti-ganti model sendiri di picker PLAN-007; (b) permintaan fitur — Text Entry ("Catat Cepat" lama) harus bisa mencatat hutang/piutang, bukan cuma transaksi.

- **Root cause 404 (kali ini):** flag `supportsStructured` katalog itu metadata level-MODEL; dukungan nyata per-ENDPOINT provider bisa lebih sempit → kombinasi `response_format`+`reasoning`+`require_parameters` sering tanpa endpoint utk model pilihan bebas user.
- **Fix: tangga fallback deterministik, model-agnostik** di `OpenRouterParser.complete()` — attempt 1 (structured+reasoning low) → attempt 2 (structured, tanpa reasoning) → attempt 3 (non-structured prompt-JSON). `OpenRouterRequestError.noEndpoints` (typed) dari client memicu percobaan berikutnya; semua gagal → arahkan user ganti model di Pengaturan.
- **Fitur hutang di Text Entry:** `QuickEntry` enum (`.transaction`/`.debt`) + `DebtDraft`; `parseEntry` jadi requirement protokol `TransactionParsing` dengan **default `.transaction`** (engine Apple/mock tak perlu berubah). Schema OpenRouter tambah `record_kind`/`counterparty`/`direction`. Hasil debt → sheet `DebtFormView(.confirmDraft(draft))` prefilled, tetap dikonfirmasi user (pipeline sakral tak dilanggar). Siri intent masih transaksi-only (backlog).
- Commit: `f3e67b1` (ladder+debt) → `2f57f88` (docs).

## Tiga fix reaktif pasca-PLAN-008 (live user, belum ada plan doc sendiri — dicatat di sini)

User coba `gpt-oss-20b:free` dgn entry hutang, tiga gagal-decode BERBEDA muncul BERTURUT-TURUT — tiap satu diperbaiki lalu muncul modus gagal baru (provider ini benar-benar tak konsisten formatnya):

1. **`ed909b3`** — 200 OK tapi `content` = JSON valid + teks nyasar setelahnya (kebocoran channel reasoning "harmony" gpt-oss). Fix: decode toleran (strict dulu → `extractJSONObject`) dipakai utk SEMUA mode, bukan cuma non-structured.
2. **`b1c2d90`** — masih gagal decode (159 bytes, tak ke-log isinya → buta). Fix: `GeneratedTransaction` decode LENTUR (amount terima number ATAU string "20.000"; field lain optional, tak menggagalkan seluruh decode bila satu field beda tipe/hilang) + jalur unwrap double-encoded (content = STRING JSON berisi objek) + log 300 char pertama saat semua gagal (diagnostik, bukan asumsi).
3. **`1fac01f`** — ternyata `gpt-oss-20b:free` kadang **MENGABAIKAN `response_format` TOTAL** dan balas key-value/YAML mentah (`amount: 10000`, `owner: i_owe`, dst, alias beda-beda per model: `owner`≠direction, `keterangan`≠note). Fix: `parseLooseKeyValue` sbg fallback TERAKHIR — parse baris `key: value`, peta alias, wajib nominal>0 (jangan terima teks acak).

**Pelajaran tercatat:** `gpt-oss-20b:free` tidak reliable untuk structured outputs meski metadata bilang dukung — kalau user pilih model ini, rantai fallback lengkap dipakai. Model default (`google/gemma-4-26b-a4b-it:free`) jauh lebih patuh JSON — disarankan ke user sbg default/utama, gpt-oss sbg cadangan saja.

92 test hijau di titik ini (naik dari 63 di awal sesi).

## Graphify — knowledge graph diperbarui

`/graphify --update` dijalankan setelah PLAN-004..008: 55 file berubah (48 code + 7 doc) → AST 863 node/1630 edge + semantic 1 chunk subagent (55 node/65 edge, 3 hyperedge) → merge ke graph lama → **1041 node, 2173 edge, 36 komunitas** (naik dari 526 node awal sesi). Health check OK (nol dangling/collapsed). Cost kumulatif: 342,934 in / 7,500 out (2 run). Satu edge AMBIGUOUS tersisa: hubungan `Upload Resi (PhotosPicker in-app)` ↔ `OpenRouterParser` (drift dokumentasi PLAN-004→006, belum ditelusuri).

## Status verifikasi tertunda (device / user)

- Menu "+" tap-through; Upload Resi end-to-end (galeri → parser pilihan → simpan+gambar); Text Entry live parse (Apple lokal = device-only untuk teks); snippet ramping + auto-close "Edit di App".
- Sync iCloud antar device (masih tertunda dari sesi 01) — kini termasuk entity baru: `DebtRecord`/`DebtPayment`, `CategorySignal`.
- Label periode di device id_ID harus "Juli 2026" (sim English menampilkan "July 2026").
- **Pengaturan → Model AI**: user perlu coba kombinasi engine (terutama Apple-gambar = OCR offline murni tanpa network) dan verifikasi Text Entry hutang di device fisik.
- gpt-oss-20b:free kalau dipilih user lagi — rantai fallback (ladder + decode lentur + key-value) belum full-loop diverifikasi live end-to-end sekaligus dalam satu request (tiap fix diverifikasi bertahap dari laporan terpisah).

## Langkah selanjutnya

1. **Merge/PR `external-model/v1` ke `main`** — SEMUA kerja PLAN-006/007/008 masih di branch ini, belum digabung. Prioritas #1 sebelum sesi berikutnya lupa.
2. User: coba lagi kombinasi model di Model AI, verifikasi fallback gpt-oss tak lagi error, verifikasi Text Entry hutang end-to-end di device.
3. Backlog: Siri intent utk hutang (kini Text Entry-only); dueDate dari kalimat NL; Voice, batch, notifikasi jatuh tempo, asset management (visi user); preset cepat Model AI ("Tercepat"/"Privasi penuh"/"Gratis terbaik").
4. Rapikan seed demo (kategori income nempel ke expense — artefak seed).
5. Telusuri edge AMBIGUOUS graphify (Upload Resi ↔ OpenRouterParser) bila mau riwayat pipeline resi 100% akurat di graph.

## Peta dokumen

Sesi 01 → `01-context-window.md`. Plan chain sesi ini: `PLAN-004` (dashboard+capture) → `PLAN-005` (hutang) → `PLAN-006` (pivot OpenRouter) → `PLAN-007` (pilih model per-peran) → `PLAN-008` (fallback+debt entry). Knowledge graph → `graphify-out/graph.html` (1041 node; `graphify query "<pertanyaan>"`). **Branch kerja: `external-model/v1`.**
