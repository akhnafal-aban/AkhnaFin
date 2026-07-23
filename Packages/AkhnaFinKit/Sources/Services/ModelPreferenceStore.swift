import Foundation
import ServiceInterfaces

/// Preferensi model di UserDefaults (JSON) — BUKAN Keychain: pilihan model
/// bukan rahasia; hanya API key yang di Keychain.
///
/// `@unchecked Sendable`: `UserDefaults` thread-safe (didokumentasikan Apple)
/// tapi belum dianotasi Sendable di SDK — pembungkus ini immutable.
public final class ModelPreferenceStore: ModelPreferenceStoring, @unchecked Sendable {
    private static let key = "modelPreference.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ModelPreference {
        guard let data = defaults.data(forKey: Self.key),
              let preference = try? JSONDecoder().decode(ModelPreference.self, from: data) else {
            return .standard
        }
        return preference
    }

    public func save(_ preference: ModelPreference) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
