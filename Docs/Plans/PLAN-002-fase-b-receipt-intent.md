# PLAN-002 — Fase B: Receipt Screenshot via Shortcut

- **Status:** Selesai (implementasi + unit + sim, 2026-07-09) — gerbang device (B5) menunggu checklist user
- **Catatan pivot:** parser resi = heuristik deterministik `ReceiptHeuristics`, BUKAN Foundation Models — FM menolak semua prompt berisi teks Indonesia (`unsupportedLanguageOrLocale`, empiris; amplop English pun gagal). Bekerja tanpa Apple Intelligence.
- **Dibuat:** 2026-07-04
- **Induk:** PLAN-000-master-roadmap

Tujuan: user selesai bayar → screenshot resi → Shortcut → analisis → **konfirmasi di luar app** (perilaku sama intent A3) → tersimpan + gambar resi tercatat.

## Langkah

**B0. Riset API (SDK-first).** `IntentFile`/param gambar App Intents (supportedContentTypes); Vision `RecognizeDocumentsRequest` (iOS 26; fallback `RecognizeTextRequest`); ketersediaan Vision di macOS 26 untuk unit test.

**B1. `VisionReceiptScanner: ReceiptScanning` di `Services`.**
- `extractText(from: Data) async throws -> String` (baris tersusun; perluas protokol bila butuh struktur — protokol di `ServiceInterfaces`, mock diperbarui).
- Unit test dgn fixture PNG resi di test bundle (Vision jalan di macOS saat `swift test`).

**B2. Parser resi.** `FoundationModelsParser.parseReceipt(text:) -> TransactionDraft` (atau `@Generable` khusus resi: total, merchant, tanggal, saran kategori) — prompt terpisah; korpus eval ≥5 teks resi fixture.

**B3. `LogReceiptIntent` di `Intents/`.** `@Parameter` gambar (IntentFile image) → scanner → parseReceipt → **konfirmasi snippet A3 sama** → `repository.commit(draft, source: .receipt)` + set `receiptImageData` (`@Attribute(.externalStorage)` sudah ada). Tambah ke `RezekiShortcuts` ("Log receipt in …").

**B4. Resep Shortcut.** `Docs/SHORTCUT-RESI.md`: Shortcuts → "Take Screenshot" → "Log Receipt (My RezekiKu)"; opsional otomatisasi; langkah uji.

**B5. Gerbang verifikasi.**
- Unit: scanner fixture + parser resi eval + regresi penuh.
- Device (user): resi nyata → screenshot → Shortcut → konfirmasi di luar app → cek transaksi + gambar di tab Transaksi; gagal OCR → error ramah.

## Setelah Fase B: BERHENTI

Backlog diparkir (JANGAN kerjakan): Voice/Speech, batch UI, dashboard, SettingsFeature, LocationService, iOS 27 enhancement, widget. Next step user: template prompt design system Claude Design (tunggu permintaan).
