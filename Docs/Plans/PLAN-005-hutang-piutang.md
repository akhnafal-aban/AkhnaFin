# PLAN-005 — Hutang/Piutang (Debt Ledger)

- **Status:** Selesai (verifikasi device oleh user tertunda)
- **Dibuat:** 2026-07-19
- **Commit range:** `3c2ad68` (Slice A) → `9af85c1` (fix donut)
- **Induk:** PLAN-004 §7 (kandidat yang dieksekusi)

## 1. Konteks & keputusan user

Fitur hutang/piutang, diminta user saat planning Fase C dan dieksekusi setelahnya.
- **Ledger TERPISAH dari kas** — tak pernah membuat `MoneyTransaction` otomatis
  (pengalaman user: model terhubung kas rumit).
- **Cicilan wajib** — termasuk paylater (SPayLater, GoPayLater, dst):
  `counterparty` teks bebas, orang ATAU platform.
- **Kartu di Dashboard (setelah Ringkasan) + layar kelola.**
- **dueDate opsional tanpa notifikasi** (notif lokal = fase nanti).
- **Visi tercatat, BELUM dibangun:** asset management — depresiasi aset, asset
  value, kategori aset. Jangan dikerjakan tanpa diminta.

## 2. Model & aturan

- `DebtRecord` / `DebtPayment` / `DebtDirection` di `AkhnaFinCore` —
  CloudKit-compliant (default/optional, inverse, tanpa unique), payments cascade.
- **Status lunas DIHITUNG** (`remaining`/`isSettled`/`isOverdue`), tidak disimpan
  — tak ada flag desinkron; overpay clamp 0.
- **Lunasi = pembayaran sebesar sisa** — satu mekanisme dgn cicilan, idempotent.
- `DebtSummary.outstanding` → kartu Dashboard (hanya sisa yang belum lunas).
- `DebtRepository` (`Persistence`): create tervalidasi (counterparty non-kosong,
  nominal > 0), addPayment, settle, fetchAll (terlambat → jatuh tempo → lunas).
- Skema: entity baru = additive → terverifikasi launch atas store lama tanpa crash.

## 3. UI

- `Features/Debts/`: `DebtListView` (section Belum Lunas/Lunas, overdue = ikon +
  teks merah — HIG bukan warna saja), `DebtFormView` (arah segmented, AmountField
  reuse, toggle jatuh tempo), `DebtDetailView` (progres, riwayat cicilan, Bayar
  Cicilan sheet default sisa, Lunasi via confirmationDialog).
- Dashboard: Section "Hutang" setelah Ringkasan (tampil juga saat periode kosong
  — hutang independen periode) → NavigationLink layar kelola.
- Wiring: `AppDependencies.debtRepository`, inject via init (pola proyek).

## 4. Bug ditemukan & fix (PENTING untuk chart berikutnya)

**Crash:** `Charts/ConcreteScale+Discrete.swift:96: Unexpectedly found nil` saat
donut pakai `.foregroundStyle(by:)` + `.chartForegroundStyleScale(domain:range:)`
(sim iOS 26.x; muncul data-dependent, terverifikasi lewat bisect).
**Fix (9af85c1):** warna STATIS per `SectorMark` dari colorHex kategori +
`FlowLegend` manual. **Aturan proyek baru: hindari
`chartForegroundStyleScale(domain:range:)` — pakai warna statis + legend manual.**

## 5. Verifikasi

- 63 unit test hijau (11 baru: DebtRecord computed + DebtRepository).
- Build SUCCEEDED; sim: dashboard + kartu Hutang terisi (sisa paylater
  750k−250k=500k benar), donut warna kategori, tanpa crash.
- Migrasi additive: launch atas store lama OK.
- **Tertunda (device user):** alur tambah→cicil→lunasi via UI; sync CloudKit
  entity baru antar device.

## 6. Berikutnya (kandidat, tunggu permintaan)

- Notifikasi lokal jatuh tempo.
- Asset management (visi user): depresiasi, nilai, kategori aset → plan sendiri.
