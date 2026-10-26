import Foundation

public enum EntrySource: String, Codable, CaseIterable, Sendable {
    case manual
    case quickAdd
    case appIntent
    case voice
    case receipt
    case batch
}
