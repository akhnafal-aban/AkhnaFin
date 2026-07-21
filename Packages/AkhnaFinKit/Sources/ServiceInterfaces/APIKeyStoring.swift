import Foundation

/// Penyimpanan API key provider AI. Implementasi produksi: Keychain
/// (`OpenRouterKeyStore` di target Services); test/Preview: mock in-memory.
public protocol APIKeyStoring: Sendable {
    /// Simpan (timpa) key. String kosong = hapus.
    func save(_ key: String) throws
    /// `nil` bila belum ada.
    func read() -> String?
    func delete() throws
}

/// Mock in-memory untuk test & Preview — TIDAK menyentuh Keychain.
public final class MockAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    public init(initialKey: String? = nil) {
        stored = initialKey
    }

    public func save(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        stored = key.isEmpty ? nil : key
    }

    public func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func delete() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
