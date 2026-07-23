import Foundation
import AkhnaFinCore
import ServiceInterfaces

/// Ekstraktor resi deterministik (aturan, bukan LLM).
///
/// KEPUTUSAN DESAIN: Foundation Models menolak SEMUA prompt yang mengandung teks
/// Indonesia (`unsupportedLanguageOrLocale`, terverifikasi empiris — bahkan bila
/// dibungkus instruksi English). Resi toko Indonesia pasti berisi kata Indonesia,
/// jadi jalur LLM mustahil untuk resi. Domain resi sempit & berstruktur (baris
/// TOTAL + angka) sehingga aturan justru lebih andal: deterministik, instan,
/// jalan tanpa Apple Intelligence, dan sepenuhnya unit-testable.
enum ReceiptHeuristics {
    /// Ekstrak draft dari teks OCR; `nil` bila tidak ada nominal total yang ditemukan.
    static func draft(from ocrText: String, now: Date = .now) -> TransactionDraft? {
        let lines = ocrText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty, let total = totalAmount(in: lines) else { return nil }

        let (category, subcategory) = categoryHint(in: ocrText)
        return TransactionDraft(
            amount: total,
            type: .expense,
            date: now,
            note: itemsSummary(in: lines),
            merchant: merchantName(in: lines),
            categoryName: category,
            subcategoryName: subcategory,
            rawInput: String(ocrText.prefix(500))
        )
    }

    // MARK: - Total

    /// Prioritas keyword: GRAND TOTAL > TOTAL (bukan subtotal) > JUMLAH = NOMINAL >
    /// PEMBAYARAN = TAGIHAN. Pada keyword sama, ambil kemunculan terakhir.
    /// `nominal`/`pembayaran` mencakup e-receipt app pembayaran (Livin, SeaBank,
    /// ShopeePay, Shopee) yang tak memakai kata "TOTAL" klasik.
    private static let totalKeywords: [(pattern: String, score: Int)] = [
        ("grand\\s*total", 4),
        ("(?<!sub[\\s-])total", 3),
        ("jumlah", 2),
        ("nominal", 2),
        ("pembayaran", 1),
        ("tagihan", 1),
    ]

    /// Baris yang TIDAK boleh dianggap total: subtotal, biaya/admin, potongan,
    /// promo/poin/cashback, kembalian/tunai. Mencegah salah ambil pada e-receipt
    /// (mis. "Biaya Transaksi", "+ Rp100 Saldo", banner promo "Rp1.000.000").
    private static let excludeFromTotalPattern =
        "sub\\s*total|biaya|admin|sisa|saldo|poin|promo|cashback|reward|kembali|tunai"

    /// Skor keyword tertinggi untuk sebuah baris (nil bila bukan baris total).
    private static func keywordScore(_ lower: String) -> Int? {
        for (pattern, score) in totalKeywords
        where lower.range(of: pattern, options: .regularExpression) != nil {
            return score
        }
        return nil
    }

    private static func totalAmount(in lines: [String]) -> Decimal? {
        var best: (score: Int, index: Int, amount: Decimal)?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.range(of: excludeFromTotalPattern, options: .regularExpression) == nil,
                  let score = keywordScore(lower) else { continue }
            // Nominal bisa sebaris dengan keyword (struk toko) ATAU di baris
            // berikutnya (e-receipt 2 kolom: label kiri, angka kanan → OCR pisah baris).
            guard let amount = amount(in: line) ?? lookaheadAmount(lines, after: index),
                  amount > 0 else { continue }
            if best == nil || score > best!.score || (score == best!.score && index > best!.index) {
                best = (score, index, amount)
            }
        }
        if let best { return best.amount }
        // Fallback e-receipt tanpa keyword total (mis. ShopeePay "-Rp87.800"):
        // nominal ber-prefix "Rp" paling atas = headline transaksi.
        return headlineAmount(in: lines)
    }

    /// Angka pada 1–2 baris non-kosong sesudah `index` (e-receipt kolom terpisah).
    private static func lookaheadAmount(_ lines: [String], after index: Int) -> Decimal? {
        for offset in 1...2 {
            let next = index + offset
            guard next < lines.count else { break }
            if let amount = amount(in: lines[next]), amount > 0 { return amount }
        }
        return nil
    }

    /// Nominal ber-prefix "Rp" pertama dari atas, lewati baris promo/saldo/biaya.
    /// Prefix "Rp" wajib agar tak salah ambil nomor rekening/PAN/ref/terminal.
    private static func headlineAmount(in lines: [String]) -> Decimal? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains("rp"),
                  lower.range(of: excludeFromTotalPattern, options: .regularExpression) == nil,
                  let amount = amount(in: line), amount > 0 else { continue }
            return amount
        }
        return nil
    }

    /// Angka nominal di akhir baris. Dua bentuk: bertitik ribuan "121.148" /
    /// "30.000,50" (prefix Rp opsional, trailing `,-`/`-` opsional), ATAU
    /// digit polos tanpa pemisah "25000" (struk thermal/POS digital).
    private static let amountPattern =
        "(?:rp\\.?\\s*)?([0-9]{1,3}(?:[.,][0-9]{3})+(?:,[0-9]{1,2})?|[0-9]{3,9}(?:,[0-9]{1,2})?)[\\s,\\-]*$"

    private static func amount(in line: String) -> Decimal? {
        guard let match = line.range(
            of: amountPattern,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        var digits = String(line[match])
            .replacingOccurrences(of: "(?i)rp\\.?\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,-"))
        // Koma terakhir diikuti 1–2 digit = desimal; sisanya pemisah ribuan.
        if let commaRange = digits.range(of: ",[0-9]{1,2}$", options: .regularExpression) {
            let decimalPart = digits[commaRange].replacingOccurrences(of: ",", with: ".")
            digits = digits[..<commaRange.lowerBound]
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "") + decimalPart
        } else {
            digits = digits
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: "")
        }
        return Decimal(string: digits)
    }

    // MARK: - Merchant & item

    /// Label penerima pada e-receipt (baris label berdiri sendiri, nilai di baris
    /// berikutnya — layout 2 kolom dipisah OCR). "Dari"/"Sumber Dana" sengaja
    /// TIDAK ada di sini (itu pengirim, bukan merchant).
    private static let merchantLabels: Set<String> = [
        "ke", "bayar ke", "penerima", "merchant", "tujuan", "kepada",
    ]

    /// Kata header/status yang bukan nama merchant (untuk fallback baris-atas).
    private static let merchantNoisePattern =
        "\\b(hasil|pembayaran|transfer|berhasil|sukses|success|rincian|transaction|details?|struk|receipt|resi|diterima|summary)\\b"

    private static func merchantName(in lines: [String]) -> String {
        // 1) E-receipt: label eksplisit → nilai = baris berikutnya yang tampak nama.
        for (index, line) in lines.enumerated() {
            let key = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            guard merchantLabels.contains(key) else { continue }
            for candidate in lines.dropFirst(index + 1).prefix(2) where isNameLike(candidate) {
                return candidate
            }
        }
        // 2) Struk toko: baris teratas yang tampak nama (skip header/status app).
        for line in lines.prefix(4) {
            guard line.lowercased().range(of: merchantNoisePattern, options: .regularExpression) == nil,
                  isNameLike(line) else { continue }
            return line
        }
        return ""
    }

    /// Nama plausible: cukup banyak huruf, bukan nomor rekening/ref (deret ≥7 digit).
    private static func isNameLike(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        guard letters >= 3, letters * 2 >= line.count else { return false }
        return line.range(of: "[0-9]{7,}", options: .regularExpression) == nil
    }

    /// Baris ringkasan pembayaran/pajak — bukan item belanjaan.
    private static let nonItemPattern =
        "sub\\s*total|total|jumlah|tagihan|ppn|pajak|diskon|discount|tunai|kembali|cash|change|debit|kredit|qris|dpp"

    /// Baris item: ada huruf + diakhiri angka (harga), sebelum baris total; nama tanpa harga.
    private static func itemsSummary(in lines: [String], maxItems: Int = 6) -> String {
        var items: [String] = []
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if totalKeywords.contains(where: { lower.range(of: $0.pattern, options: .regularExpression) != nil }) {
                break
            }
            if lower.range(of: Self.nonItemPattern, options: .regularExpression) != nil {
                continue
            }
            guard line.contains(where: \.isLetter), let priceRange = line.range(
                of: "\\s+(?:rp\\.?\\s*)?[0-9]{1,3}(?:[.,][0-9]{3})*(?:,[0-9]{1,2})?\\s*$",
                options: [.regularExpression, .caseInsensitive]
            ) else { continue }
            let name = line[..<priceRange.lowerBound].trimmingCharacters(in: .whitespaces)
            if name.count >= 3 { items.append(name) }
            if items.count == maxItems { break }
        }
        return items.joined(separator: ", ")
    }

    // MARK: - Kategori (keyword → seed kategori user)

    private static let categoryKeywords: [(keywords: [String], category: String, subcategory: String)] = [
        (["apotek", "farma", "klinik", "clinic", "pharma"], "Kesehatan", ""),
        (["spbu", "pertamina", "shell", "parkir", "parking", "tol ", "toll", "gojek", "grab", "bluebird"], "Transport", ""),
        (["indomaret", "alfamart", "alfamidi", "minimarket", "circle k"], "Lifestyle", "Jajan"),
        (["kopi", "coffee", "cafe", "café"], "Lifestyle", "Jajan"),
        (["bioskop", "cinema", "xxi", "cgv", "game"], "Lifestyle", "Hiburan"),
        (["gym", "fitness", "futsal", "badminton", "sport"], "Lifestyle", "Olahraga"),
        (["pln", "pdam", "telkom", "indihome", "wifi", "internet", "pulsa", "listrik"], "Tagihan", ""),
        (["resto", "restaurant", "warung", "rumah makan", "bakso", "sate", "nasi", "ayam", "kfc", "mcd", "burger", "pizza"], "Main Food", ""),
    ]

    private static func categoryHint(in text: String) -> (String, String) {
        let lower = text.lowercased()
        for entry in categoryKeywords where entry.keywords.contains(where: lower.contains) {
            return (entry.category, entry.subcategory)
        }
        return ("", "")
    }
}
