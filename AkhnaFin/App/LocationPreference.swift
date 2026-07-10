//
//  LocationPreference.swift
//  AkhnaFin
//
//  Sumber tunggal preferensi "Rekam Lokasi" — dibaca View (@AppStorage) DAN
//  kode commit (non-view). Default ON (keputusan Fase 0: auto-capture senyap).
//

import Foundation

enum LocationPreference {
    static let key = "recordLocation"

    /// Default true: kunci yang belum pernah diset dianggap aktif — konsisten dgn
    /// `@AppStorage("recordLocation") = true` di SettingsView.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
