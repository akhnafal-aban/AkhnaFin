# PLAN-003 — Settings Lengkap

- **Status:** Aktif
- **Dibuat:** 2026-07-10
- **Induk:** PLAN-000-master-roadmap (item backlog "SettingsFeature", dibuka atas permintaan user pasca Fase B)
- **Commit range:** mulai setelah `aec255f`

Tujuan: ganti placeholder Pengaturan jadi Settings fungsional — (1) kelola kategori CRUD+subkategori, (2) toggle "Rekam lokasi" + implementasi `LocationService` (CoreLocation, auto-capture senyap di commit dalam-app), (3) status sync iCloud. Pertahankan arsitektur (logic di package, UI di app), pipeline, SDK-first, commit per slice + test hijau.

## Slice

**S1. Status iCloud + skeleton Settings.**
- `AppContainer`: rekam mode aktif → `private(set) static var activeStorageMode: ModelContainerFactory.StorageMode`; set di `makeContainer()`.
- `Features/Settings/SettingsView.swift` (pindah dari placeholder di RootView): section Penyimpanan (iCloud aktif / Lokal + penjelasan), Tentang (versi). Section Kategori & Lokasi = navigation ke layar slice berikут (stub dulu).

**S2. LocationService + toggle.**
- Riset SDK CoreLocation one-shot async (CLLocationUpdate/CLServiceSession vs requestLocation).
- `Services/CoreLocationService: LocationCapturing` — `captureCurrent()` one-shot + reverse geocode (`CLGeocoder`) → `CapturedPlace?`; gagal/izin ditolak → nil (tak pernah menggagalkan commit).
- Toggle `@AppStorage("recordLocation")` (default true). Gating di app-layer: bila off → skip capture.
- Wire ke commit DALAM-APP saja (TransactionFormView.save add/confirm, QuickAdd) — intent headless dilewati (butuh izin Always). `AppDependencies` sediakan `locationService`.
- Info.plist: `NSLocationWhenInUseUsageDescription`.
- Uji: mock (sudah ada) untuk gating; service nyata di device.

**S3. Category CRUD (logic, Persistence).**
- `TransactionRepository`: `addCategory(name:iconName:colorHex:kind:parent:)`, `updateCategory`, `deleteCategory` (guard `isBuiltIn` tak bisa dihapus; hapus custom → transaksi ter-nullify via inverse), `fetchCategories(kind:)`.
- Unit test: tambah induk+sub, rename, hapus custom (transaksi jadi tanpa kategori), built-in dilindungi.

**S4. Category management UI.**
- `Features/Settings/CategoryManagementView.swift` + `CategoryEditView.swift`: list per kind (induk + sub indent), tambah/edit (nama, SF Symbol picker subset, warna, jenis, induk), swipe hapus (kecuali built-in). Pakai `@Query` untuk reaktif; mutasi lewat repository.

**S5. Verifikasi + commit.**
- Unit penuh; build; sim: buka Settings, tambah kategori muncul di picker form, toggle lokasi, status iCloud tampil.
- Device (user): izin lokasi muncul saat commit pertama; lokasi tersimpan (cek detail transaksi).

## Batas
Tetap dalam scope Settings. Backlog lain (Dashboard/Voice/Batch) tetap diparkir.
