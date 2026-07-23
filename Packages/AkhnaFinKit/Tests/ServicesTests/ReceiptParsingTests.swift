import Testing
import Foundation
import AkhnaFinCore
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

    /// E-receipt app pembayaran: layout 2 kolom → OCR (RecognizeDocuments)
    /// memisah label & nominal ke baris berbeda. Transcript di bawah = hasil OCR
    /// nyata yang terobservasi (lihat commit fix). Label "Total" klasik sering
    /// absen — dipakai "Nominal"/"Jumlah"/"Pembayaran" atau headline "Rp".
    private static let eReceipts: [(name: String, ocr: String, total: Decimal)] = [
        ("Livin",     "Total Transaksi\nRp 225.000",                                     225000),
        ("Transfer",  "Nominal\nRp 3.000",                                                 3000),
        ("SeaBank",   "Rp 25.000\nNominal Transaksi\nJumlah Total\nRp 25.000\nRp 25.000", 25000),
        ("ShopeePay", "Rincian Pembayaran\n-Rp87.800\nBerhasil\nBayar Ke",                87800),
        ("Shopee",    "Rp 30.500\nJumlah Transfer\nRp 30.500",                            30500),
    ]

    @Test("E-receipt 2 kolom (label & nominal beda baris): total benar")
    func eReceiptTwoColumn() async throws {
        for c in Self.eReceipts {
            let draft = try await parser.parseReceipt(text: c.ocr)
            #expect(draft.amount == c.total, "total \(c.name)")
            #expect(draft.type == .expense)
        }
    }

    @Test("Baris promo/saldo tidak salah jadi total (ShopeePay banner)")
    func promoNotMistakenForTotal() async throws {
        // Banner promo "Rp1.000.000" & "+ Rp100 Saldo" tak boleh menang atas 87.800.
        let draft = try await parser.parseReceipt(
            text: "Rincian Pembayaran\n-Rp87.800\nDapat Saldo Rp1.000.000\n+ Rp100 Saldo ShopeePay"
        )
        #expect(draft.amount == 87800)
    }

    @Test("Desimal koma & prefix Rp ter-parse")
    func decimalAndRpPrefix() async throws {
        let comma = try await parser.parseReceipt(text: "WARUNG A\nTOTAL 30.000,50")
        #expect(comma.amount == Decimal(string: "30000.5"))

        let rp = try await parser.parseReceipt(text: "WARUNG B\nTOTAL Rp 45.000")
        #expect(rp.amount == 45000)
    }

    @Test("Nominal tanpa pemisah ribuan & trailing Rp/,- (struk thermal/POS)")
    func plainDigitsAndTrailing() async throws {
        // Tanpa titik ribuan.
        #expect(try await parser.parseReceipt(text: "TOKO X\nTOTAL 25000").amount == 25000)
        #expect(try await parser.parseReceipt(text: "TOKO Y\nTOTAL: 5000").amount == 5000)
        // Trailing ",-" gaya Indonesia.
        #expect(try await parser.parseReceipt(text: "TOKO Z\nTOTAL Rp30.000,-").amount == 30000)
        #expect(try await parser.parseReceipt(text: "TOKO W\nGRAND TOTAL 125000 ,-").amount == 125000)
    }

    @Test("rawInput dipotong 500 chars")
    func rawInputTruncated() async throws {
        let filler = String(repeating: "Item Panjang 1.000\n", count: 60)
        let draft = try await parser.parseReceipt(text: "TOKO X\n" + filler + "TOTAL 60.000")
        #expect(draft.rawInput.count == 500)
    }

    // MARK: - E-resi nyata (transkrip OCR dari screenshot user: SeaBank, ShopeePay,
    // Livin' QRIS, Livin' transfer, app referral)

    private struct EReceiptCase: Sendable {
        let name: String
        let ocr: String
        let total: Decimal
        let merchantContains: String
    }

    private static let fullEReceipts: [EReceiptCase] = [
        .init(
            name: "SeaBank QRIS",
            ocr: """
            20.23
            Hasil Transfer
            Pembayaran Diterima
            Rp 25.000
            Dari
            Noor Akhnafal Aban
            SeaBank: 901457678857
            Ke
            SATE MADURA GUSTY 48
            JAKARTA PUSAT
            Nama Acquirer
            PERMATA
            9360-0013-1600-6042-749
            Nominal Transaksi
            Rp 25.000
            Biaya Transaksi
            GRATIS
            Jumlah Total
            Rp 25.000
            No. Transaksi
            2026071143507228515972038
            No. Referensi
            01130003N0TQ
            """,
            total: 25000, merchantContains: "SATE MADURA"
        ),
        .init(
            name: "ShopeePay",
            ocr: """
            18.09
            Rincian Pembayaran
            -Rp87.800
            Berhasil
            Waktu Selesai 11-07-2026 11:53
            Aplikasi ShopeePay
            Tukar Poin
            Dapat Saldo 1.000.000/orang
            100JT
            Bayar QRIS & Aplikasi
            Bayar Ke
            PT Astro Technologies Ind
            Rincian Promo
            Promo Dipakai
            Cashback Saldo
            Berhasil Dapat
            + Rp100 Saldo ShopeePay
            Poin Didapatkan
            Tukar Poin
            + 8 Poin
            Rincian Pesanan
            """,
            total: 87800, merchantContains: "Astro"
        ),
        .init(
            name: "Livin QRIS",
            ocr: """
            09.42
            livin'
            by mandiri
            QR Bayar
            Pembayaran Berhasil!
            25 Apr 2026 • 09:41:50 WIB • No. Ref. 2604251121564453249
            Penerima
            Be My Star
            Kota Tangerang, ID
            Detail Transaksi
            Total Transaksi
            Rp 225.000
            Sumber Dana
            JEANY AURELLIA PUTRI
            Bank Mandiri - 5781
            No. Referensi QRIS
            604254406134
            Pengakuisisi
            DANA
            Merchant PAN
            9360091532727713746
            Customer PAN
            9360000812252257818
            Terminal ID
            272771374
            """,
            total: 225000, merchantContains: "Be My Star"
        ),
        .init(
            name: "Livin transfer",
            ocr: """
            18.37
            Transfer Berhasil!
            16 Apr 2026 • 18:37:03 WIB
            Lihat Resi
            Penerima
            ANGELLA CHRISTIE
            Bank Mandiri - 1850004159379
            Nominal
            Rp 3.000
            dari JEANY AURELLIA PUTRI
            Bagikan Resi
            """,
            total: 3000, merchantContains: "ANGELLA"
        ),
        .init(
            name: "Referral bonus",
            ocr: """
            20.51
            Transaction Details
            Referral Bonus
            800IW8S1783735926533
            Transaction Summary
            Transaction ID
            800IW8S1783735926533
            Status
            Success
            Total
            Rp150.000
            Transaction Details
            Category
            Referral
            """,
            total: 150000, merchantContains: "Referral"
        ),
    ]

    @Test("E-resi nyata: total & merchant terbaca benar")
    func eReceiptCorpus() async throws {
        for c in Self.fullEReceipts {
            let draft = try await parser.parseReceipt(text: c.ocr)
            #expect(draft.amount == c.total, "\(c.name): total \(draft.amount)")
            #expect(
                draft.merchant.localizedCaseInsensitiveContains(c.merchantContains),
                "\(c.name): merchant \"\(draft.merchant)\""
            )
        }
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
