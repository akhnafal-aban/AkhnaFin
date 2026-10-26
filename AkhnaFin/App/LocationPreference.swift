//
//  LocationPreference.swift
//  AkhnaFin
//

import Foundation

enum LocationPreference {
    static let key = "recordLocation"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
