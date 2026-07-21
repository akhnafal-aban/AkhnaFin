import Foundation
import SwiftData
import AkhnaFinCore
import ServiceInterfaces

/// Tulis/baca edge `CategorySignal` — mesin personalisasi kategori (PLAN-006).
///
/// Menulis: `record` dipanggil tiap commit jalur AI. Membaca: `contextSnippet`
/// mengubah edge relevan menjadi ≤ `maxLines` baris teks untuk prompt generator
/// (hemat token — hanya asosiasi yang cocok dengan input).
@MainActor
public final class SignalRepository {
    private let context: ModelContext
    private let maxLines: Int

    public init(context: ModelContext, maxLines: Int = 12) {
        self.context = context
        self.maxLines = maxLines
    }

    // MARK: - Tulis (belajar dari commit)

    /// Rekam hasil final satu commit jalur AI.
    /// - Parameters:
    ///   - edited: user mengubah kategori dari saran model → koreksi, bobot besar.
    /// Bobot: konfirmasi +1.0, koreksi +2.5 (sinyal terkuat = user repot mengedit).
    public func record(
        merchant: String,
        bank: String,
        noteKeywords: String,
        categoryName: String,
        edited: Bool,
        now: Date = .now
    ) throws {
        let category = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { return }
        let boost = edited ? 2.5 : 1.0

        var pairs: [(SignalKind, String)] = []
        if let key = Self.normalize(merchant) { pairs.append((.merchant, key)) }
        if let key = Self.normalize(bank) { pairs.append((.bank, key)) }
        for token in Self.tokens(from: noteKeywords) {
            pairs.append((.keyword, token))
        }

        for (kind, key) in pairs {
            let kindRaw = kind.rawValue
            let descriptor = FetchDescriptor<CategorySignal>(
                predicate: #Predicate { $0.key == key && $0.categoryName == category }
            )
            let existing = try context.fetch(descriptor).first { $0.kind.rawValue == kindRaw }
            if let existing {
                existing.weight += boost
                existing.lastUsedAt = now
            } else {
                context.insert(CategorySignal(
                    kind: kind, key: key, categoryName: category, weight: boost, lastUsedAt: now
                ))
            }
        }
        try context.save()
    }

    // MARK: - Baca (konteks prompt)

    /// Edge yang key-nya muncul di `input`, dirangking bobot, dilipat per key
    /// (kategori terkuat menang), maksimal `maxLines` baris.
    public func snippet(for input: String) throws -> String {
        let inputTokens = Set(Self.tokens(from: input))
        guard !inputTokens.isEmpty else { return "" }

        let all = try context.fetch(FetchDescriptor<CategorySignal>(
            sortBy: [SortDescriptor(\.weight, order: .reverse)]
        ))
        // Cocok bila key edge muncul utuh di input (key multi-kata dicek substring).
        let lowered = input.lowercased()
        let matched = all.filter { signal in
            signal.key.contains(" ") ? lowered.contains(signal.key) : inputTokens.contains(signal.key)
        }

        // Lipat per (kind,key): kategori dengan bobot tertinggi yang mewakili.
        var seen = Set<String>()
        var lines: [String] = []
        for signal in matched {
            let dedupeKey = "\(signal.kind.rawValue)|\(signal.key)"
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)
            let strength = signal.weight >= 5 ? "strong" : "seen"
            lines.append("- \(signal.key) → \(signal.categoryName) (\(strength), \(signal.kind.rawValue))")
            if lines.count == maxLines { break }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Normalisasi

    static func normalize(_ raw: String) -> String? {
        let value = raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Kata bermakna ≥3 huruf; buang stopword umum Indonesia/English.
    static func tokens(from text: String) -> [String] {
        let stopwords: Set<String> = [
            "beli", "bayar", "buat", "yang", "untuk", "dari", "di", "ke", "dan",
            "the", "and", "for", "buy", "pay", "with", "pakai", "pake", "via",
        ]
        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) && Int($0) == nil }
    }
}

/// Adaptor `PersonalizationProviding` untuk parser (protokol Sendable, repo
/// MainActor — hop eksplisit di sini).
public struct SignalPersonalization: PersonalizationProviding {
    private let repository: SignalRepository

    public init(repository: SignalRepository) {
        self.repository = repository
    }

    public func contextSnippet(for input: String) async -> String {
        await MainActor.run {
            (try? repository.snippet(for: input)) ?? ""
        }
    }
}
