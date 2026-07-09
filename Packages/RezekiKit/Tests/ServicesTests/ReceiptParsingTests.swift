import Testing
import Foundation
import RezekiCore
import ServiceInterfaces
@testable import Services

/// Parser resi = heuristik deterministik → uji penuh TANPA model/Apple Intelligence.
@Suite("Parser resi — heuristik deterministik")
struct ReceiptParsingTests {
    private let parser = FoundationModelsParser(categoryNames: [], subcategoryNames: [])

    private struct EvalCase: Sendable {
        let ocr: String
        let total: Decimal
        let merchantContains: String
        let category: String
        let subcategory: String
    }

    private static let corpus: [EvalCase] = [
        .init(
            ocr: "TOKO MAJU JAYA\nJl. Sudirman 12\nNasi Goreng 25.000\nEs Teh 5.000\nTOTAL 30.000\nTUNAI 50.000\nKEMBALI 20.000",
            total: 30000, merchantContains: "MAJU", category: "Main Food", subcategory: ""
        ),
        .init(
            ocr: "INDOMARET\nAqua 600ml 4.500\nRoti Tawar 15.500\nSub Total 20.000\nPPN 2.200\nTOTAL 22.200",
            total: 22200, merchantContains: "INDOMARET", category: "Lifestyle", subcategory: "Jajan"
        ),
        .init(
            ocr: "KOPI KENANGAN\nAmericano 18.000\nCroissant 25.000\nDiskon -5.000\nGRAND TOTAL 38.000",
            total: 38000, merchantContains: "KENANGAN", category: "Lifestyle", subcategory: "Jajan"
        ),
        .init(
            ocr: "APOTEK K-24\nParacetamol 12.000\nVitamin C 35.000\nJUMLAH 47.000",
            total: 47000, merchantContains: "K-24", category: "Kesehatan", subcategory: ""
        ),
        .init(
            ocr: "SPBU PERTAMINA 34.123\nPertamax 9.77 L\nHarga/L 12.400\nTOTAL 121.148",
            total: 121148, merchantContains: "PERTAMINA", category: "Transport", subcategory: ""
        ),
    ]

    @Test("Korpus 5 resi: total, merchant, kategori benar")
    func corpus() async throws {
        for c in Self.corpus {
            let draft = try await parser.parseReceipt(text: c.ocr)
            #expect(draft.amount == c.total, "total \(c.merchantContains)")
            #expect(draft.merchant.localizedCaseInsensitiveContains(c.merchantContains))
            #expect(draft.type == .expense)
            #expect(draft.categoryName == c.category, "kategori \(c.merchantContains)")
            #expect(draft.subcategoryName == c.subcategory)
        }
    }

    @Test("TOTAL menang atas Sub Total; ringkasan item terbaca")
    func totalBeatsSubtotalAndItems() async throws {
        let draft = try await parser.parseReceipt(
            text: "TOKO MAJU JAYA\nNasi Goreng 25.000\nEs Teh 5.000\nSub Total 30.000\nTOTAL 33.000"
        )
        #expect(draft.amount == 33000)
        #expect(draft.note == "Nasi Goreng, Es Teh")
    }

    @Test("Desimal koma & prefix Rp ter-parse")
    func decimalAndRpPrefix() async throws {
        let comma = try await parser.parseReceipt(text: "WARUNG A\nTOTAL 30.000,50")
        #expect(comma.amount == Decimal(string: "30000.5"))

        let rp = try await parser.parseReceipt(text: "WARUNG B\nTOTAL Rp 45.000")
        #expect(rp.amount == 45000)
    }

    @Test("rawInput dipotong 500 chars")
    func rawInputTruncated() async throws {
        let filler = String(repeating: "Item Panjang 1.000\n", count: 60)
        let draft = try await parser.parseReceipt(text: "TOKO X\n" + filler + "TOTAL 60.000")
        #expect(draft.rawInput.count == 500)
    }

    @Test("Tanpa baris total / OCR kosong → parsingFailed ramah")
    func failures() async {
        await #expect(throws: TransactionParsingError.self) {
            _ = try await parser.parseReceipt(text: "TOKO X\nNasi Goreng 25.000")
        }
        await #expect(throws: TransactionParsingError.self) {
            _ = try await parser.parseReceipt(text: "   \n  ")
        }
    }
}
