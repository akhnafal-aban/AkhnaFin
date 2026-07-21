import Foundation
import SwiftData

/// Jenis node sumber pada edge perilaku kategori.
public enum SignalKind: String, Codable, CaseIterable, Sendable {
    /// Nama merchant/tempat ("indomaret", "kantin kantor").
    case merchant
    /// Kata kunci dari catatan/item ("bakso", "bensin").
    case keyword
    /// Bank / app pembayaran ("bca", "gopay", "spaylater").
    case bank
}

/// SATU EDGE berbobot pada knowledge-graph mini perilaku user (PLAN-006 Slice C):
/// `key (node sumber) --memilih--> categoryName (node kategori)` dengan bobot.
///
/// Padanan native "graphify" yang bisa jalan di iOS: node implisit, hanya edge
/// yang disimpan — retrieval murah (fetch by key), konteks prompt hemat token.
/// Direkam dari SETIAP commit jalur AI: konfirmasi = penguat (+1), hasil edit
/// user = koreksi (bobot lebih besar). Sync antar device via CloudKit.
///
/// CloudKit-compatible: semua atribut punya default, tanpa relasi, tanpa unique.
@Model
public final class CategorySignal {
    public var id: UUID = UUID()
    public var kind: SignalKind = SignalKind.keyword
    /// Node sumber, ternormalisasi lowercase-trimmed.
    public var key: String = ""
    /// Node tujuan: nama kategori (level utama) — cukup nama, resolusi ke objek
    /// kategori terjadi saat commit lewat repository yang sudah ada.
    public var categoryName: String = ""
    public var weight: Double = 0
    public var lastUsedAt: Date = Date.now

    public init(
        id: UUID = UUID(),
        kind: SignalKind = .keyword,
        key: String = "",
        categoryName: String = "",
        weight: Double = 0,
        lastUsedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.categoryName = categoryName
        self.weight = weight
        self.lastUsedAt = lastUsedAt
    }
}
