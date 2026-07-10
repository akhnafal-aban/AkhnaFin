import Foundation
import RezekiCore
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

    /// Prioritas keyword: GRAND TOTAL > TOTAL (bukan subtotal) > JUMLAH > TAGIHAN.
    /// Pada keyword sama, ambil kemunculan terakhir (total akhir lazim di bawah).
    private static let totalKeywords: [(pattern: String, score: Int)] = [
        ("grand\\s*total", 4),
        ("(?<!sub[\\s-])total", 3),
        ("jumlah", 2),
        ("tagihan", 1),
    ]

    private static func totalAmount(in lines: [String]) -> Decimal? {
        var best: (score: Int, index: Int, amount: Decimal)?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.range(of: "sub\\s*total", options: .regularExpression) == nil else { continue }
            for (pattern, score) in totalKeywords {
                guard lower.range(of: pattern, options: .regularExpression) != nil,
                      let amount = amount(in: line), amount > 0 else { continue }
                if best == nil || score > best!.score || (score == best!.score && index > best!.index) {
                    best = (score, index, amount)
                }
                break
            }
        }
        return best?.amount
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

    /// Baris pertama yang tampak seperti nama (mengandung huruf, bukan dominan angka).
    private static func merchantName(in lines: [String]) -> String {
        for line in lines.prefix(3) {
            let letters = line.filter(\.isLetter).count
            if letters >= 3, letters * 2 >= line.count { return line }
        }
        return ""
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
