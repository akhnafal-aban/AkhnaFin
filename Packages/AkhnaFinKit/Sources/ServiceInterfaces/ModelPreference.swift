import Foundation

/// Engine parser yang bisa dipilih user per peran (PLAN-007).
public enum ParserEngine: Codable, Equatable, Sendable {
    /// On-device Apple: teks via Foundation Models (English-only, butuh Apple
    /// Intelligence), resi via Vision OCR + heuristik (offline).
    case appleLocal
    /// Model OpenRouter pilihan user dari katalog. `supportsStructured` disimpan
    /// bersama slug: menentukan jalur response_format vs prompt-JSON toleran.
    case openRouter(slug: String, supportsStructured: Bool, displayName: String)

    public var displayName: String {
        switch self {
        case .appleLocal: "Apple (Lokal)"
        case .openRouter(_, _, let name): name
        }
    }
}

/// Preferensi engine per PERAN — teks dan gambar bebas beda engine/model.
public struct ModelPreference: Codable, Equatable, Sendable {
    public var text: ParserEngine
    public var image: ParserEngine

    public init(text: ParserEngine, image: ParserEngine) {
        self.text = text
        self.image = image
    }

    /// Default = perilaku PLAN-006 terakhir: Gemma 4 26B A4B utk kedua peran.
    public static let standard = ModelPreference(
        text: .openRouter(
            slug: "google/gemma-4-26b-a4b-it:free",
            supportsStructured: true,
            displayName: "Gemma 4 26B A4B (free)"
        ),
        image: .openRouter(
            slug: "google/gemma-4-26b-a4b-it:free",
            supportsStructured: true,
            displayName: "Gemma 4 26B A4B (free)"
        )
    )
}

/// Penyimpanan preferensi model (bukan rahasia — UserDefaults di produksi).
public protocol ModelPreferenceStoring: Sendable {
    func load() -> ModelPreference
    func save(_ preference: ModelPreference)
}

/// Mock in-memory untuk test & Preview.
public final class MockModelPreferenceStore: ModelPreferenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ModelPreference

    public init(initial: ModelPreference = .standard) {
        stored = initial
    }

    public func load() -> ModelPreference {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ preference: ModelPreference) {
        lock.lock(); defer { lock.unlock() }
        stored = preference
    }
}
