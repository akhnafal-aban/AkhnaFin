import Testing
import Foundation
import SwiftData
@testable import Persistence
import AkhnaFinCore

@MainActor
@Suite("SignalRepository — knowledge graph mini kategori")
struct SignalRepositoryTests {
    private func makeRepository(maxLines: Int = 12) throws -> SignalRepository {
        SignalRepository(
            context: ModelContext(try ModelContainerFactory.make(mode: .inMemory)),
            maxLines: maxLines
        )
    }

    @Test("Record membuat edge merchant+keyword; konfirmasi +1, koreksi +2.5")
    func recordWeights() throws {
        let repository = try makeRepository()
        try repository.record(
            merchant: "Indomaret", bank: "GoPay", noteKeywords: "beli sabun mandi",
            categoryName: "Main Food", edited: false
        )
        try repository.record(
            merchant: "Indomaret", bank: "", noteKeywords: "",
            categoryName: "Main Food", edited: true
        )
        let snippet = try repository.snippet(for: "belanja indomaret pakai gopay")
        #expect(snippet.contains("indomaret → Main Food"))
        #expect(snippet.contains("gopay → Main Food"))
        // 1.0 + 2.5 = 3.5 < 5 → masih "seen"
        #expect(snippet.contains("seen"))
    }

    @Test("Bobot ≥5 dilabeli strong")
    func strongLabel() throws {
        let repository = try makeRepository()
        for _ in 0..<2 {
            try repository.record(
                merchant: "SPayLater", bank: "", noteKeywords: "",
                categoryName: "Tagihan", edited: true
            )
        }
        let snippet = try repository.snippet(for: "bayar spaylater")
        #expect(snippet.contains("strong"))
    }

    @Test("Snippet hanya berisi edge yang cocok dengan input")
    func snippetRelevanceOnly() throws {
        let repository = try makeRepository()
        try repository.record(
            merchant: "Indomaret", bank: "", noteKeywords: "",
            categoryName: "Main Food", edited: false
        )
        try repository.record(
            merchant: "Shell", bank: "", noteKeywords: "bensin",
            categoryName: "Transport", edited: false
        )
        let snippet = try repository.snippet(for: "isi bensin di shell")
        #expect(snippet.contains("shell"))
        #expect(snippet.contains("bensin"))
        #expect(!snippet.contains("indomaret"))
    }

    @Test("Input tanpa kecocokan → snippet kosong; kategori kosong → tak direkam")
    func emptyCases() throws {
        let repository = try makeRepository()
        try repository.record(
            merchant: "X Store", bank: "", noteKeywords: "",
            categoryName: "", edited: false
        )
        #expect(try repository.snippet(for: "apa saja") == "")
    }

    @Test("Tokenizer: stopword & angka dibuang, normalisasi lowercase")
    func tokenizer() {
        let tokens = SignalRepository.tokens(from: "Beli Bakso 20000 di Kantin pakai GoPay")
        #expect(tokens.contains("bakso"))
        #expect(tokens.contains("kantin"))
        #expect(tokens.contains("gopay"))
        #expect(!tokens.contains("beli"))
        #expect(!tokens.contains("20000"))
        #expect(SignalRepository.normalize("  Indomaret ") == "indomaret")
        #expect(SignalRepository.normalize("   ") == nil)
    }

    @Test("Key multi-kata dicocokkan sebagai substring input")
    func multiWordKey() throws {
        let repository = try makeRepository()
        try repository.record(
            merchant: "Kantin Kantor", bank: "", noteKeywords: "",
            categoryName: "Main Food", edited: false
        )
        let snippet = try repository.snippet(for: "makan siang di kantin kantor")
        #expect(snippet.contains("kantin kantor → Main Food"))
    }
}
