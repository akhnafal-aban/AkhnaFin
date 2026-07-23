# PLAN-007 — Konfigurasi Model AI per-Peran (Apple lokal ⇄ OpenRouter)

- **Status:** Selesai (verifikasi UI live oleh user tertunda)
- **Dibuat:** 2026-07-23
- **Commit range:** `3599c7c` (restore Apple) → `9a9b7c2` (Settings UI) + docs
- **Induk:** PLAN-006 (lanjutan — user menilai single-model free belum efisien)

## 1. Konteks

Data live single-call Gemma: 4.6s / 10.7s / **25.2s timeout** / 3s — variance
provider free tak tertebak. Keputusan user: kendali penuh — **pilih engine per
peran** (parsing teks & parsing gambar terpisah): Apple lokal ATAU model
OpenRouter apa pun dari katalog. Semua fitur lain tetap (personalisasi,
Keychain, snippet, dsb.).

## 2. Arsitektur

```
ModelPreferenceStore (UserDefaults, bukan rahasia)
  text / image : .appleLocal | .openRouter(slug, supportsStructured, nama)
        │  dibaca SAAT CALL (ganti setting langsung berlaku)
        ▼
RoutingTransactionParser (TransactionParsing — protokol TAK berubah)
  ├ .appleLocal → AppleTransactionParser
  │    teks   → FoundationModelsParser (restored dari c8ca853^; English-only,
  │             gagal di sim — batasan FM iOS 26)
  │    gambar → VisionReceiptScanner → ReceiptHeuristics (offline, tanpa AI)
  └ .openRouter → OpenRouterParser
       slug+structured per peran dari preferensi; model non-structured →
       prompt-JSON + extractJSONObject (restored)
```

- `availability` = engine TEKS (graceful state QuickAdd); engine gambar dicek saat parseReceipt.
- Personalisasi `CategorySignal` disuntik ke SEMUA engine (FM instructions ikut — paritas).
- Katalog: `OpenRouterModelCatalog` (actor) — `GET /api/v1/models` publik tanpa key;
  map image-capable (`architecture.input_modalities`), structured
  (`supported_parameters`), harga/1M token, flag `:free`.

## 3. UI (Pengaturan → Model AI)

Per peran: baris "Apple (Lokal)" (checkmark) + baris "OpenRouter" →
`ModelPickerView`: searchable, toggle "Hanya Gratis" (default ON), filter
otomatis image-capable utk peran gambar, badge JSON (structured) + harga +
ikon foto, pull-to-refresh. Footnote jujur per peran (English-only FM; OCR
offline).

## 4. Keputusan teknis

| Keputusan | Alasan |
|---|---|
| Preferensi di UserDefaults, bukan Keychain | Pilihan model bukan rahasia; Keychain khusus API key |
| Resolve engine saat call | Ganti setting langsung berlaku tanpa rebuild DI |
| FM dibungkus `AppleTransactionParser` | Protokol kini `parseReceipt(image:)`; OCR+heuristik jadi detail internal |
| `extractJSONObject` direstorasi | User bebas pilih model tanpa structured outputs |
| `ModelPreference.standard` = Gemma 4 26B A4B | Kontinuitas perilaku PLAN-006 |
| Store `@unchecked Sendable` | UserDefaults thread-safe (docs Apple) tapi belum dianotasi Sendable |

## 5. Verifikasi

- 83 test hijau (routing per peran, slug per peran, jalur non-structured,
  campuran Apple-teks+OpenRouter-gambar, store roundtrip, + test heuristik/OCR
  yang direstorasi).
- Build SUCCEEDED; boot sim bersih.
- **Tertunda (user):** tap-through Pengaturan → Model AI → ganti kombinasi;
  Apple-gambar di sim harus jalan OFFLINE (heuristik); FM teks di sim =
  graceful state (expected); timing per model tetap ter-log
  (`call <slug> selesai dalam …`).

## 6. Backlog terkait

- Preset cepat ("Tercepat", "Privasi penuh = Apple semua", "Gratis terbaik").
- Simpan preferensi ke CloudKit (kini per-device by design — beda device boleh beda model).
- Asset management (visi user, belum dibangun).
