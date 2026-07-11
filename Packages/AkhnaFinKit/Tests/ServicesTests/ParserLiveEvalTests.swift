import Testing
import Foundation
import AkhnaFinCore
import ServiceInterfaces
@testable import Services

/// Eval kualitas parser dgn model SUNGGUHAN (BUG-1a — kualitas harus terukur).
/// Hanya jalan bila host punya Apple Intelligence aktif (Mac M-series);
/// di CI/simulator otomatis ter-skip. Jalankan lokal:
/// `DEVELOPER_DIR=... swift test --filter ParserLiveEvalTests`
@Suite(
    "Parser live eval (butuh Apple Intelligence host)",
    .enabled(if: FoundationModelsParser(categoryNames: [], subcategoryNames: []).availability == .available)
)
struct ParserLiveEvalTests {
    private struct EvalCase: Sendable {
        let text: String
        let amount: Decimal
        let type: TransactionType
        /// Kategori/subkategori yang diharapkan (nil = tak dinilai).
        let category: String?
    }

    private static let corpus: [EvalCase] = [
        .init(text: "buy meatballs 20k at the office canteen", amount: 20000, type: .expense, category: "Main Food"),
        .init(text: "lunch 35k", amount: 35000, type: .expense, category: "Main Food"),
        .init(text: "coffee 18k at starbucks", amount: 18000, type: .expense, category: nil),
        .init(text: "pay electricity 350k yesterday", amount: 350000, type: .expense, category: "Tagihan"),
        .init(text: "internet bill 299k", amount: 299000, type: .expense, category: "Tagihan"),
        .init(text: "monthly rent 2.5m", amount: 2_500_000, type: .expense, category: "Tagihan"),
        .init(text: "salary came in 5.73m this month", amount: 5_730_000, type: .income, category: "Gaji"),
        .init(text: "got a bonus 1m from work", amount: 1_000_000, type: .income, category: "Bonus"),
        .init(text: "grab ride to the airport 125k", amount: 125_000, type: .expense, category: "Transport"),
        .init(text: "parking 5k", amount: 5000, type: .expense, category: "Transport"),
        .init(text: "fuel 100k at pertamina", amount: 100_000, type: .expense, category: "Transport"),
        .init(text: "movie tickets 50k two days ago", amount: 50000, type: .expense, category: "Hiburan"),
        .init(text: "netflix subscription 186k", amount: 186_000, type: .expense, category: nil),
        .init(text: "gym membership 300k", amount: 300_000, type: .expense, category: "Olahraga"),
        .init(text: "badminton court 80k", amount: 80000, type: .expense, category: "Olahraga"),
        .init(text: "snacks 12k at indomaret", amount: 12000, type: .expense, category: "Jajan"),
        .init(text: "medicine 45k at the pharmacy", amount: 45000, type: .expense, category: "Kesehatan"),
        .init(text: "doctor visit 250k yesterday", amount: 250_000, type: .expense, category: "Kesehatan"),
        .init(text: "dinner with family 175k", amount: 175_000, type: .expense, category: "Main Food"),
        .init(text: "transfer 500k to savings account", amount: 500_000, type: .transfer, category: nil),
    ]

    @Test("Akurasi korpus ≥90% (amount & type), kategori dilaporkan", .timeLimit(.minutes(10)))
    func corpusAccuracy() async throws {
        let parser = FoundationModelsParser(
            categoryNames: ["Main Food", "Lifestyle", "Tagihan", "Transport", "Kesehatan", "Gaji", "Bonus"],
            subcategoryNames: ["Jajan", "Hiburan", "Olahraga"]
        )

        var amountHits = 0, typeHits = 0, categoryHits = 0, categoryTotal = 0
        var failures: [String] = []

        for c in Self.corpus {
            let draft = try await parser.parse(c.text)
            if draft.amount == c.amount { amountHits += 1 } else {
                failures.append("AMOUNT \"\(c.text)\": dapat \(draft.amount), harap \(c.amount)")
            }
            if draft.type == c.type { typeHits += 1 } else {
                failures.append("TYPE \"\(c.text)\": dapat \(draft.type.rawValue), harap \(c.type.rawValue)")
            }
            if let expected = c.category {
                categoryTotal += 1
                if draft.categoryName == expected || draft.subcategoryName == expected {
                    categoryHits += 1
                } else {
                    failures.append("CATEGORY \"\(c.text)\": dapat \(draft.categoryName)/\(draft.subcategoryName), harap \(expected)")
                }
            }
        }

        let n = Self.corpus.count
        let amountAcc = Double(amountHits) / Double(n)
        let typeAcc = Double(typeHits) / Double(n)
        let catAcc = categoryTotal > 0 ? Double(categoryHits) / Double(categoryTotal) : 1
        print("=== PARSER EVAL === amount \(amountHits)/\(n) (\(Int(amountAcc * 100))%), type \(typeHits)/\(n) (\(Int(typeAcc * 100))%), category \(categoryHits)/\(categoryTotal) (\(Int(catAcc * 100))%)")
        failures.forEach { print("  MISS: \($0)") }

        // Target PLAN-001 A4: amount & type ≥90%. Kategori dilaporkan (informatif).
        #expect(amountAcc >= 0.9, "akurasi amount \(Int(amountAcc * 100))% < 90%")
        #expect(typeAcc >= 0.9, "akurasi type \(Int(typeAcc * 100))% < 90%")
    }
}
