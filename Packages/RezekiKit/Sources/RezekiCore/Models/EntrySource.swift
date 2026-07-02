import Foundation

/// Asal pencatatan sebuah transaksi — dipakai untuk audit & analitik jalur input.
public enum EntrySource: String, Codable, CaseIterable, Sendable {
    case manual
    case appIntent
    case voice
    case receipt
    case batch
}
