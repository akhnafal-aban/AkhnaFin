# PLAN-006 — Rework Core AI: Foundation Models → OpenRouter

- **Status:** Selesai (verifikasi live butuh API key user — lihat §6)
- **Dibuat:** 2026-07-21
- **Commit range:** `f837149` (Slice A) → `a7f3032` (Slice D) + docs
- **Induk:** PLAN-000 (pivot arsitektur atas permintaan eksplisit user)

## 1. Keputusan & alasan

User pivot dari Apple-native ke OpenRouter (punya API key sendiri):
- **2-stage:** `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free` (perception —
  teks Indonesia/English ATAU foto resi, multimodal tanpa OCR) →
  `openai/gpt-oss-120b:free` (transaction generator, structured outputs).
- **Jalur Apple-native DIHAPUS TOTAL** (FoundationModelsParser, VisionReceiptScanner,
  ReceiptHeuristics): satu pipeline, tanpa dual-maintenance.
- **Free tier** (pilihan sadar user). Trade-off tercatat: provider free dapat
  me-log/melatih dari data; rate limit → pesan 429 khusus; timeout pipeline 25s.
- **API key: Keychain** (`OpenRouterKeyStore`, kSecAttrAccessibleAfterFirstUnlock)
  diinput via SecureField Pengaturan; tak pernah UserDefaults/log/ditampilkan ulang.
- **Personalisasi = knowledge-graph mini di SwiftData** (`CategorySignal`: edge
  berbobot merchant|keyword|bank → kategori), BUKAN graphify runtime — graphify
  tool dev di Mac, tak bisa jalan di iOS. Konsep sama, native.

## 2. Bonus pivot

- Input **Bahasa Indonesia didukung** (FM dulu menolak semua teks Indonesia).
- Parser **jalan di simulator** (FM inference gagal di sim) → seluruh jalur AI
  kini verifiable tanpa device.
- Kode −1065 baris (heuristik resi & OCR mati).

## 3. Arsitektur (boundary tetap)

```
teks/gambar → OpenRouterParser(Services)
  stage1 Nemotron → fakta {amount,kind,days_ago,merchant,bank,note}
  stage2 gpt-oss-120b + kategori user + snippet CategorySignal → TransactionDraft
→ konfirmasi user (form/snippet) → commit → SwiftData+CloudKit
→ SignalRepository.record (konfirmasi +1.0 / edit +2.5) → parse berikutnya
```
- `ServiceInterfaces`: `APIKeyStoring`, `PersonalizationProviding`,
  `parseReceipt(image:)` (menggantikan `parseReceipt(text:)` + `ReceiptScanning`).
- `Services`: `OpenRouterKeyStore`, `OpenRouterClient` (structured outputs strict +
  `provider.require_parameters`, error mapping 401/402/429/offline), `OpenRouterParser`.
- `Persistence`: `SignalRepository` (+ `SignalPersonalization` adaptor).
- Referensi docs: openrouter.ai/docs/quickstart, docs/features/structured-outputs.

## 4. Feedback loop personalisasi (permintaan inti user)

Setiap commit jalur AI: `TransactionFormView.confirmDraft` (tahu edit vs terima)
dan `SaveDraftIntent` (snippet Simpan = tanpa edit) → `SignalRepository.record`.
Parse berikutnya: `snippet(for: input)` menyuntikkan ≤12 baris asosiasi RELEVAN
("indomaret → Main Food (strong)") ke prompt stage 2 — hemat token. Sync antar
device via CloudKit (model additive, aman container existing — boot atas store
lama terverifikasi tanpa crash).

## 5. Verifikasi

- 64 unit test hijau (transport URLProtocol mock, parser 2-stage stub, signals);
  race handler statis antar suite diperbaiki (URLProtocol per suite).
- Build SUCCEEDED; sim boot bersih atas data lama.
- **Menunggu user (butuh key — Claude tak memegang credential):** paste key di
  Pengaturan → Text Entry "beli bakso 20k di kantin" → draft → simpan; Upload
  Resi → draft + gambar; snippet Siri Simpan/Edit/Batal di device; cek koreksi
  kategori 2× lalu lihat saran berubah.

## 5b. Fix pasca-verifikasi live user (routing)

Live pertama gagal: **"No endpoints found that can handle the requested parameters."**
Root cause (models API `supported_parameters`, otoritatif):
- Nemotron omni `:free` TIDAK punya `response_format` → `json_schema strict` +
  `require_parameters:true` tak punya endpoint. **Fix:** Stage 1 `structured:false`,
  minta JSON via prompt, ekstrak objek JSON toleran (`extractJSONObject`, hormati
  string literal & fences reasoning).
- `openai/gpt-oss-120b:free` **tidak ada** (hanya paid). **Fix:** Stage 2 →
  `openai/gpt-oss-20b:free` (keluarga gpt-oss, gratis, dukung structured outputs).
- Client: parameter `structured` — set `response_format`+`require_parameters`
  HANYA bila true. 67 test hijau.
- Alternatif (belum dipakai): `openai/gpt-oss-120b` paid ($0.03/M) bila mau 120b
  — ganti satu konstanta `OpenRouterModel.generator`.

## 5c. Collapse 2-stage → 1-stage (permintaan user, setelah data live)

User ukur live sebelum fix reasoning: 23.2s (16.1+7.1). Setelah `reasoning.effort:
"low"`: **7.9s** (6.7+1.16) — user tetap minta lebih efisien: satu model saja,
kategori sepenuhnya dibantu `SignalRepository` (bukan cuma hint prompt).

Riset kandidat model tunggal gratis + multimodal (via `GET /api/v1/models`,
`supported_parameters`, uptime per-provider):

| Model | Params aktif | Structured native | Uptime provider |
|---|---|---|---|
| **google/gemma-4-26b-a4b-it:free** ✅ dipilih | MoE, **3.8B/token** | ✅ | 2 provider, ~99% |
| google/gemma-4-31b-it:free | Dense, 30.7B | ✅ | 1 provider, ~99% |
| nvidia/nemotron-nano-12b-v2-vl:free | 12B | ❌ | 1 provider, **74%** |

Dipilih **Gemma 4 26B A4B**: MoE paling ringan + native `response_format`
(hapus workaround `extractJSONObject` yang jadi tak relevan) + provider ganda
(lebih stabil dari opsi 1-provider). Keputusan user tambahan: kategori **tetap
ditebak model** (bukan murni lookup `SignalRepository`) — daftar kategori +
snippet personalisasi tetap masuk prompt SATU call itu; `SignalRepository`
tetap sumber personalisasi, bukan generator kedua.

**Arsitektur baru:** `OpenRouterParser.complete()` — satu method, satu call,
schema = fields lama `GeneratedTransaction` (amount/type/days_ago/merchant/
note/category_name/subcategory_name). `PerceivedFacts`, `perceive()`,
`generate()`, `extractJSONObject` (khusus workaround non-structured Nemotron)
dihapus — semua dead code stage-2 terpisah.

**Trade-off didokumentasikan:** personalisasi pre-call hanya jalan untuk jalur
teks (rawInput sudah berisi kandidat merchant/keyword sebelum call). Jalur
resi TIDAK dapat personalisasi pre-call — merchant baru diketahui model
SETELAH ia membaca gambar, dalam call yang sama; tak ada call kedua untuk
memakainya. Kategori resi tetap bisa benar lewat daftar kategori di prompt,
hanya tanpa dorongan riwayat personal.

Commit: lihat log setelah `ff4b2bb` (reasoning fix) — rewrite `OpenRouterParser`
+ `OpenRouterModel` + test suite. 67 test hijau; build SUCCEEDED. Timing satu-
call BELUM diukur live (menunggu user).

## 6. Backlog terkait

- Optimasi: lipat 2 call jadi 1 call multimodal bila latensi free tier terasa.
- Decay bobot sinyal berbasis waktu; UI inspeksi/reset sinyal di Pengaturan.
- Visi user (belum dibangun): asset management (depresiasi, nilai, kategori).
