import Foundation

public protocol APIKeyStoring: Sendable {
    func save(_ key: String) throws
    func read() -> String?
    func delete() throws
}

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