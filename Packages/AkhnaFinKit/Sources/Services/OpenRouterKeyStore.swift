import Foundation
import Security
import ServiceInterfaces

/// API key OpenRouter di Keychain (kSecClassGenericPassword) — pendekatan
/// native pengelolaan credential: tidak pernah UserDefaults/plist/hardcode.
/// Nilai key hanya mengalir user → SecureField Pengaturan → Keychain → header
/// Authorization; tidak pernah ditampilkan kembali atau masuk log.
public struct OpenRouterKeyStore: APIKeyStoring {
    private let service = "com.aban.AkhnaFin.openrouter"
    private let account = "api-key"

    public init() {}

    public enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                "Gagal mengakses Keychain (status \(status))."
            }
        }
    }

    public func save(_ key: String) throws {
        guard !key.isEmpty else {
            try delete()
            return
        }
        let data = Data(key.utf8)
        // Timpa bila sudah ada: hapus dulu, lalu tambah (SecItemUpdate juga bisa,
        // delete+add lebih sederhana dan idempotent).
        try delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Cukup saat device pernah unlock — intent bisa jalan background.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // Item tidak ada = bukan error (idempotent).
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
