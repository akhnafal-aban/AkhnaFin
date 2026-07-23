import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let parserLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Parser")
private let parserSignposter = OSSignposter(subsystem: "com.aban.AkhnaFin", category: "Parser")

/// Parser SATU-CALL berbasis OpenRouter (PLAN-006, disederhanakan dari 2-stage
/// awal setelah pengukuran live: 2 call berantai = 23.2s; model tunggal
/// memangkas satu round-trip network penuh).
///
/// Satu model multimodal (`OpenRouterModel.model`) mengerjakan sekaligus:
/// teks (Indonesia/English) ATAU foto resi → ekstraksi fakta + tebakan
/// kategori (dibantu daftar kategori user + konteks personalisasi
/// `CategorySignal`). Hasil SELALU draft yang dikonfirmasi user.
///
/// Trade-off sadar: personalisasi hanya bisa disuntik SEBELUM call untuk jalur
/// teks (merchant belum diketahui untuk resi sampai model membacanya sendiri
/// di call yang sama) — kategori resi tetap bisa benar lewat daftar kategori
/// di prompt, hanya tanpa dorongan riwayat personal di kesempatan itu.
public struct OpenRouterParser: TransactionParsing {
    private let client: OpenRouterClient
    private let keyStore: any APIKeyStoring
    private let categoryNames: [String]
    private let subcategoryNames: [String]
    private let personalization: (any PersonalizationProviding)?
    /// Slug + kemampuan structured dibaca SAAT CALL dari preferensi user
    /// (PLAN-007) — ganti model di Pengaturan langsung berlaku.
    private let preferenceStore: any ModelPreferenceStoring

    public init(
        client: OpenRouterClient,
        keyStore: any APIKeyStoring,
        categoryNames: [String],
        subcategoryNames: [String],
        personalization: (any PersonalizationProviding)? = nil,
        preferenceStore: any ModelPreferenceStoring = MockModelPreferenceStore()
    ) {
        self.client = client
        self.keyStore = keyStore
        self.categoryNames = categoryNames
        self.subcategoryNames = subcategoryNames
        self.personalization = personalization
        self.preferenceStore = preferenceStore
    }

    /// Slug + flag structured untuk peran; bila preferensi peran itu bukan
    /// OpenRouter (RoutingParser salah kirim / default), pakai standar.
    private func engineConfig(imageRole: Bool) -> (slug: String, structured: Bool) {
        let preference = preferenceStore.load()
        let engine = imageRole ? preference.image : preference.text
        if case .openRouter(let slug, let structured, _) = engine {
            return (slug, structured)
        }
        if case .openRouter(let slug, let structured, _) = (imageRole ? ModelPreference.standard.image : ModelPreference.standard.text) {
            return (slug, structured)
        }
        return (OpenRouterModel.model, true)
    }

    public var availability: ParsingAvailability {
        if let key = keyStore.read(), !key.isEmpty {
            return .available
        }
        return .unavailable(
            reason: "Masukkan API key OpenRouter di Pengaturan untuk mengaktifkan pencatatan AI."
        )
    }

    // MARK: - TransactionParsing

    public func parse(_ text: String) async throws -> TransactionDraft {
        // Jalur lama (intent Siri, batch): hasil hutang pun dipaksa jadi draft
        // transaksi agar tak ada jalur commit tanpa konfirmasi bentuk baru.
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        let snippet = await personalization?.contextSnippet(for: text) ?? ""
        let generated = try await complete(parts: [.text(text)], hint: .sentence, personalizationSnippet: snippet, imageRole: false)
        return generated.draft(rawInput: text)
    }

    /// PLAN-008: kalimat bisa menghasilkan transaksi ATAU catatan hutang.
    public func parseEntry(_ text: String) async throws -> QuickEntry {
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        let snippet = await personalization?.contextSnippet(for: text) ?? ""
        let generated = try await complete(parts: [.text(text)], hint: .sentence, personalizationSnippet: snippet, imageRole: false)
        return generated.isDebt
            ? .debt(generated.debtDraft(rawInput: text))
            : .transaction(generated.draft(rawInput: text))
    }

    public func parseBatch(_ text: String) async throws -> [TransactionDraft] {
        var drafts: [TransactionDraft] = []
        for line in text.split(whereSeparator: \.isNewline) {
            drafts.append(try await parse(String(line)))
        }
        return drafts
    }

    public func parseReceipt(image: Data) async throws -> TransactionDraft {
        let interval = parserSignposter.beginInterval("parse")
        defer { parserSignposter.endInterval("parse", interval) }
        // Tanpa personalisasi pre-call: merchant resi belum diketahui sebelum
        // model membaca gambar di call yang sama (trade-off single-stage).
        let generated = try await complete(parts: [.image(image)], hint: .receipt, personalizationSnippet: "", imageRole: true)
        return generated.draft(rawInput: "")
    }

    // MARK: - Satu call: persepsi + kategorisasi

    private enum InputHint { case sentence, receipt }

    struct GeneratedTransaction: Decodable {
        let amount: Double
        let type: String
        let daysAgo: Int
        let merchant: String
        let note: String
        let categoryName: String
        let subcategoryName: String

        let recordKind: String
        let counterparty: String
        let direction: String

        enum CodingKeys: String, CodingKey {
            case amount, type, merchant, note, counterparty, direction
            case daysAgo = "days_ago"
            case categoryName = "category_name"
            case subcategoryName = "subcategory_name"
            case recordKind = "record_kind"
        }

        /// Field hutang opsional saat decode (model non-structured bisa
        /// melewatkannya) — default aman: transaksi.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Lentur: model/provider tertentu mengirim angka sebagai string
            // ("20000") atau melewatkan field — jangan gagalkan seluruh decode.
            if let value = try? container.decode(Double.self, forKey: .amount) {
                amount = value
            } else if let text = try? container.decode(String.self, forKey: .amount),
                      let value = Double(text.replacingOccurrences(of: ".", with: "")
                          .replacingOccurrences(of: ",", with: "")) {
                amount = value
            } else {
                amount = 0
            }
            type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "expense"
            if let days = try? container.decodeIfPresent(Int.self, forKey: .daysAgo) {
                daysAgo = days
            } else if let text = try? container.decodeIfPresent(String.self, forKey: .daysAgo) {
                daysAgo = Int(text) ?? 0
            } else {
                daysAgo = 0
            }
            merchant = (try? container.decodeIfPresent(String.self, forKey: .merchant)) ?? ""
            note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? ""
            categoryName = (try? container.decodeIfPresent(String.self, forKey: .categoryName)) ?? ""
            subcategoryName = (try? container.decodeIfPresent(String.self, forKey: .subcategoryName)) ?? ""
            recordKind = (try? container.decodeIfPresent(String.self, forKey: .recordKind)) ?? "transaction"
            counterparty = (try? container.decodeIfPresent(String.self, forKey: .counterparty)) ?? ""
            direction = (try? container.decodeIfPresent(String.self, forKey: .direction)) ?? "none"
        }

        init(
            amount: Double, type: String, daysAgo: Int,
            merchant: String, note: String, categoryName: String, subcategoryName: String,
            recordKind: String = "transaction", counterparty: String = "", direction: String = "none"
        ) {
            self.amount = amount
            self.type = type
            self.daysAgo = daysAgo
            self.merchant = merchant
            self.note = note
            self.categoryName = categoryName
            self.subcategoryName = subcategoryName
            self.recordKind = recordKind
            self.counterparty = counterparty
            self.direction = direction
        }

        /// Hutang valid = record_kind debt + counterparty terisi.
        var isDebt: Bool {
            recordKind == "debt" && !counterparty.trimmingCharacters(in: .whitespaces).isEmpty
        }

        func debtDraft(rawInput: String) -> DebtDraft {
            DebtDraft(
                counterparty: counterparty,
                direction: direction == "owed_to_me" ? .owedToMe : .iOwe,
                amount: sanitizedRupiah(amount),
                note: note,
                rawInput: rawInput
            )
        }

        /// Mapping murni (tanpa network) ke draft — unit-testable.
        func draft(rawInput: String, now: Date = .now, calendar: Calendar = .current) -> TransactionDraft {
            let daysBack = max(0, daysAgo)
            let date = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
            return TransactionDraft(
                amount: sanitizedRupiah(amount),
                type: TransactionType(rawValue: type) ?? .expense,
                date: date,
                note: note,
                merchant: merchant,
                categoryName: categoryName,
                subcategoryName: subcategoryName,
                rawInput: rawInput
            )
        }
    }

    private static let schema = """
    {"type":"object","properties":{"record_kind":{"type":"string","enum":["transaction","debt"],"description":"debt ONLY when the sentence is about lending/borrowing money (utang, piutang, pinjam, paylater bill); otherwise transaction"},"amount":{"type":"number","description":"Amount in full rupiah. k=thousand (20k=20000), m/jt=million. For receipts: the FINAL GRAND TOTAL paid."},"type":{"type":"string","enum":["expense","income","transfer"]},"days_ago":{"type":"integer","description":"today=0, yesterday/kemarin=1, two days ago/kemarin lusa=2"},"merchant":{"type":"string","description":"Store/seller/place name; empty if unknown"},"note":{"type":"string","description":"Short summary"},"category_name":{"type":"string","description":"Best-matching MAIN category name from the provided list; empty if unsure"},"subcategory_name":{"type":"string","description":"Matching subcategory from the provided list; empty otherwise"},"counterparty":{"type":"string","description":"For debt: person or platform name (Budi, SPayLater); empty for transaction"},"direction":{"type":"string","enum":["i_owe","owed_to_me","none"],"description":"For debt: i_owe = the user borrowed/owes money; owed_to_me = someone owes the user; none for transaction"}},"required":["record_kind","amount","type","days_ago","merchant","note","category_name","subcategory_name","counterparty","direction"],"additionalProperties":false}
    """

    private func complete(
        parts: [ORContentPart],
        hint: InputHint,
        personalizationSnippet: String,
        imageRole: Bool
    ) async throws -> GeneratedTransaction {
        let config = engineConfig(imageRole: imageRole)

        // Tangga fallback utk 404 "No endpoints found" (kombinasi parameter tak
        // punya endpoint — tergantung model yang user pilih): full → tanpa
        // reasoning → tanpa structured. Deterministik & ter-log; error lain
        // langsung dilempar.
        var attempts: [(structured: Bool, effort: String?)] = [(config.structured, "low")]
        if config.structured {
            attempts.append((true, nil))
        }
        attempts.append((false, nil))

        var lastError: Error = TransactionParsingError.parsingFailed("Gagal memproses.")
        for (index, attempt) in attempts.enumerated() {
            do {
                return try await runAttempt(
                    parts: parts, hint: hint,
                    personalizationSnippet: personalizationSnippet,
                    slug: config.slug, structured: attempt.structured,
                    reasoningEffort: attempt.effort
                )
            } catch OpenRouterRequestError.noEndpoints {
                parserLog.warning("no-endpoints attempt \(index + 1)/\(attempts.count) (structured=\(attempt.structured)) — coba varian lebih longgar")
                lastError = TransactionParsingError.parsingFailed(
                    "Model ini tidak kompatibel dengan permintaan app. Pilih model lain di Pengaturan → Model AI."
                )
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func runAttempt(
        parts: [ORContentPart],
        hint: InputHint,
        personalizationSnippet: String,
        slug: String,
        structured: Bool,
        reasoningEffort: String?
    ) async throws -> GeneratedTransaction {
        var instruction = switch hint {
        case .sentence:
            """
            You are a personal-finance parser. Convert the user's sentence (Indonesian \
            or English) into a structured record. Amount rules: k=×1000, jt/m=×1000000; \
            never round or add zeros.
            record_kind is "debt" ONLY for lending/borrowing sentences (utang, piutang, \
            pinjam, paylater bills): "utang ke Budi 50k" → debt, i_owe, counterparty Budi; \
            "Budi pinjam 100k" → debt, owed_to_me. Regular purchases/income → transaction.
            """
        case .receipt:
            """
            You are a personal-finance parser reading a shopping receipt image (usually \
            Indonesian). Extract the FINAL grand total actually paid (after discounts/tax \
            — the largest TOTAL line), the merchant name, and summarize items briefly in \
            `note`. type is always "expense", days_ago 0 unless a clear date shows otherwise.
            """
        }
        instruction += """

        Available main categories: \(Self.describe(categoryNames)).
        Available subcategories: \(Self.describe(subcategoryNames)).
        Category names are Indonesian. Output the exact NAME, only from those lists; \
        empty string if unsure.
        """
        if !personalizationSnippet.isEmpty {
            instruction += "\n\nUser's known category habits (strong hints, follow when relevant):\n\(personalizationSnippet)"
        }
        // Model/attempt tanpa structured outputs: minta JSON via prompt lalu
        // ekstrak toleran — mesin yang sama dgn workaround 2-stage dulu.
        if !structured {
            instruction += """


            Return ONLY a single JSON object, no markdown fences, no commentary:
            {"record_kind": "transaction"|"debt", "amount": number (full rupiah), \
            "type": "expense"|"income"|"transfer", "days_ago": integer, \
            "merchant": string, "note": string, "category_name": string, \
            "subcategory_name": string, "counterparty": string, \
            "direction": "i_owe"|"owed_to_me"|"none"}
            """
        }

        let clock = ContinuousClock()
        let start = clock.now
        let data = try await client.completeStructured(
            model: slug,
            messages: [.system(instruction), .user(parts)],
            schemaName: "generated_transaction",
            schemaJSON: Self.schema,
            structured: structured,
            reasoningEffort: reasoningEffort
        )
        parserLog.info("call \(slug, privacy: .public) selesai dalam \(clock.now - start, privacy: .public)")

        // Decode toleran utk SEMUA mode: sebagian provider membocorkan teks di
        // sekitar JSON meski structured (mis. channel reasoning gpt-oss) —
        // coba strict dulu, gagal → ekstrak objek JSON seimbang.
        if let generated = try? JSONDecoder().decode(GeneratedTransaction.self, from: data) {
            return generated
        }
        if let extracted = Self.extractJSONObject(from: data),
           let generated = try? JSONDecoder().decode(GeneratedTransaction.self, from: extracted) {
            parserLog.info("decode sukses via ekstraksi toleran (content tak murni JSON)")
            return generated
        }
        // Kasus double-encoded: content = STRING JSON berisi objek ("{\"a\":1}").
        if let unwrapped = try? JSONDecoder().decode(String.self, from: data),
           let generated = try? JSONDecoder().decode(GeneratedTransaction.self, from: Data(unwrapped.utf8)) {
            parserLog.info("decode sukses via unwrap string ganda")
            return generated
        }
        // Diagnostik: tampilkan isi mentah (terpotong) — tanpa ini kegagalan
        // berikutnya tak bisa didiagnosis dari log.
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-utf8>"
        parserLog.error("decode gagal (\(data.count) bytes, structured=\(structured)): \(preview, privacy: .public)")
        throw TransactionParsingError.parsingFailed(
            "Gagal memahami input itu. Coba tulis ulang lebih jelas."
        )
    }

    /// Ekstrak objek JSON pertama yang seimbang dari respons non-structured
    /// (model bisa membungkus dgn fences/prosa). Hormati string literal & escape.
    static func extractJSONObject(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { inString = false }
            } else {
                switch char {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index]).data(using: .utf8)
                    }
                default: break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Glossary kategori (port dari parser lama — BUG-1a)

    private static let glossary: [String: String] = [
        "Main Food": "daily meals",
        "Lifestyle": "leisure & hobbies",
        "Jajan": "snacks / street food / coffee",
        "Hiburan": "entertainment: movies, games, streaming, concerts",
        "Olahraga": "sports & fitness: gym, badminton, futsal, swimming, running gear",
        "Tagihan": "bills & utilities: electricity, water, internet, rent, subscriptions",
        "Transport": "transportation: fuel, parking, ride-hailing, public transit",
        "Kesehatan": "health & medical",
        "Gaji": "salary / wages",
        "Bonus": "bonus / incentives / gifts received",
    ]

    private static func describe(_ names: [String]) -> String {
        names
            .map { name in glossary[name].map { "\(name) (= \($0))" } ?? name }
            .joined(separator: ", ")
    }
}

/// Double → Decimal dibulatkan 2 digit (hindari artefak floating-point), minimum 0.
/// (Dipindah dari FoundationModelsParser saat pivot PLAN-006.)
func sanitizedRupiah(_ amount: Double) -> Decimal {
    var value = Decimal(max(0, amount))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    return rounded
}
