# PLAN-008 — Tangga Fallback No-Endpoints + Text Entry Hutang

- **Status:** Selesai (verifikasi live user tertunda)
- **Dibuat:** 2026-07-23
- **Commit:** `f3e67b1`
- **Induk:** PLAN-007

## 1. Bug fix: 404 "No endpoints found"

Live user (LogExpense): kombinasi `response_format` + `reasoning` +
`provider.require_parameters` tak punya endpoint untuk model pilihan user —
flag `supportsStructured` katalog adalah metadata level-MODEL, dukungan nyata
per-ENDPOINT provider bisa lebih sempit.

**Fix (model-agnostik, deterministik):** `OpenRouterRequestError.noEndpoints`
(typed, dari client) → tangga fallback di parser per call:
1. structured + `reasoning.effort:"low"`
2. structured tanpa reasoning
3. non-structured (prompt-JSON + `extractJSONObject`)

Semua gagal → pesan: pilih model lain di Pengaturan → Model AI. Tiap attempt
ter-log (`no-endpoints attempt n/3`).

## 2. Fitur: Text Entry mencatat hutang/piutang

"utang ke Budi 50k" → DebtDraft (i_owe, Budi); "Budi pinjam 100k" → owed_to_me.

- `QuickEntry` enum (.transaction/.debt) + `DebtDraft` (ServiceInterfaces).
- `parseEntry` requirement `TransactionParsing` + default `.transaction` —
  engine Apple/mock tak berubah.
- Schema OpenRouter + `record_kind`/`counterparty`/`direction`; field hutang
  optional saat decode (model non-structured bisa melewatkan); guard `isDebt`
  (debt tanpa counterparty → transaksi).
- UI: QuickAddView hasil debt → sheet `DebtFormView(.confirmDraft(draft))`
  prefilled — **tetap konfirmasi user sebelum simpan** (pipeline sakral).
- Siri intent: masih transaksi-only (backlog).

## 3. Verifikasi

87 test hijau (ladder 3-attempt urutan parameter, all-fail message, debt vs
transaksi, guard counterparty kosong) · build SUCCEEDED.
**User:** ulangi kalimat yang tadi 404 (harus jalan — maksimal jatuh ke jalur
non-structured); coba "utang ke Budi 50k" di Text Entry → form hutang prefilled.

## 4. Backlog

- Siri intent hutang ("catat utang ke Budi 50k" via snippet).
- dueDate dari kalimat ("jatuh tempo bulan depan") → DebtDraft.
