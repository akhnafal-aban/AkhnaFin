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

## 6. Backlog terkait

- Optimasi: lipat 2 call jadi 1 call multimodal bila latensi free tier terasa.
- Decay bobot sinyal berbasis waktu; UI inspeksi/reset sinyal di Pengaturan.
- Visi user (belum dibangun): asset management (depresiasi, nilai, kategori).
