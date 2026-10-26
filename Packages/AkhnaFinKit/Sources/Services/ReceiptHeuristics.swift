import Foundation
import AkhnaFinCore
import ServiceInterfaces

enum ReceiptHeuristics {
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

    private static let totalKeywords: [(pattern: String, score: Int)] = [
        ("grand\\s*total", 4),
        ("(?<!sub[\\s-])total", 3),
        ("jumlah", 2),
        ("nominal", 2),
        ("pembayaran", 1),
        ("tagihan", 1),
    ]

    private static let excludeFromTotalPattern =
        "sub\\s*total|biaya|admin|sisa|saldo|poin|promo|cashback|reward|kembali|tunai"

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
            guard let amount = amount(in: line) ?? lookaheadAmount(lines, after: index),
                  amount > 0 else { continue }
            if best == nil || score > best!.score || (score == best!.score && index > best!.index) {
                best = (score, index, amount)
            }
        }
        if let best { return best.amount }
        return headlineAmount(in: lines)
    }

    private static func lookaheadAmount(_ lines: [String], after index: Int) -> Decimal? {
        for offset in 1...2 {
            let next = index + offset
            guard next < lines.count else { break }
            if let amount = amount(in: lines[next]), amount > 0 { return amount }
        }
        return nil
    }

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

    private static let merchantLabels: Set<String> = [
        "ke", "bayar ke", "penerima", "merchant", "tujuan", "kepada",
    ]

    private static let merchantNoisePattern =
        "\\b(hasil|pembayaran|transfer|berhasil|sukses|success|rincian|transaction|details?|struk|receipt|resi|diterima|summary)\\b"

    private static func merchantName(in lines: [String]) -> String {
        for (index, line) in lines.enumerated() {
            let key = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            guard merchantLabels.contains(key) else { continue }
            for candidate in lines.dropFirst(index + 1).prefix(2) where isNameLike(candidate) {
                return candidate
            }
        }
        for line in lines.prefix(4) {
            guard line.lowercased().range(of: merchantNoisePattern, options: .regularExpression) == nil,
                  isNameLike(line) else { continue }
            return line
        }
        return ""
    }

    private static func isNameLike(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        guard letters >= 3, letters * 2 >= line.count else { return false }
        return line.range(of: "[0-9]{7,}", options: .regularExpression) == nil
    }

    private static let nonItemPattern =
        "sub\\s*total|total|jumlah|tagihan|ppn|pajak|diskon|discount|tunai|kembali|cash|change|debit|kredit|qris|dpp"

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
