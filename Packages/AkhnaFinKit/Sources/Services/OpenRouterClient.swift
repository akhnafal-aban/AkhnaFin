import Foundation
import OSLog
import ServiceInterfaces

private let clientLog = Logger(subsystem: "com.aban.AkhnaFin", category: "OpenRouter")

/// Slug model OpenRouter yang dipakai pipeline (keputusan PLAN-006, free tier).
public enum OpenRouterModel {
    /// Stage 1 — perception/parser multimodal (teks + gambar resi).
    /// Tak dukung structured outputs (dipanggil `structured: false`).
    public static let perception = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free"
    /// Stage 2 — transaction generator (structured outputs, free tier).
    /// `gpt-oss-120b:free` TIDAK ADA di OpenRouter — hanya paid; `gpt-oss-20b:free`
    /// = anggota keluarga gpt-oss gratis yang dukung structured outputs.
    public static let generator = "openai/gpt-oss-120b"
}

/// Satu bagian isi pesan chat (teks atau gambar).
public enum ORContentPart: Sendable {
    case text(String)
    /// JPEG/PNG mentah — dikirim sebagai data URL base64 (format OpenAI-style
    /// `image_url`, sesuai docs OpenRouter).
    case image(Data)
}

public struct ORChatMessage: Sendable {
    public let role: String
    public let parts: [ORContentPart]

    public static func system(_ text: String) -> ORChatMessage {
        ORChatMessage(role: "system", parts: [.text(text)])
    }

    public static func user(_ parts: [ORContentPart]) -> ORChatMessage {
        ORChatMessage(role: "user", parts: parts)
    }
}

/// Transport tipis ke `POST /api/v1/chat/completions` OpenRouter dengan
/// structured outputs (`response_format: json_schema, strict`).
///
/// Referensi: https://openrouter.ai/docs/quickstart ,
/// https://openrouter.ai/docs/features/structured-outputs
public struct OpenRouterClient: Sendable {
    private let keyStore: any APIKeyStoring
    private let session: URLSession
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    public init(keyStore: any APIKeyStoring, session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    /// Kirim chat completion dan kembalikan `message.content` (string JSON hasil
    /// structured output) sebagai `Data` siap-decode.
    ///
    /// `schemaJSON` = JSON Schema mentah (string literal statis di pemanggil —
    /// Sendable-safe untuk Swift 6 strict concurrency).
    ///
    /// `structured`: kirim `response_format json_schema strict` + `require_parameters`.
    /// HARUS false untuk model yang tak dukung structured outputs (mis. Nemotron
    /// omni :free) — bila true di model tsb, OpenRouter membalas "No endpoints
    /// found that can handle the requested parameters" (terverifikasi lewat
    /// models API `supported_parameters`).
    public func completeStructured(
        model: String,
        messages: [ORChatMessage],
        schemaName: String,
        schemaJSON: String,
        structured: Bool = true
    ) async throws -> Data {
        guard let apiKey = keyStore.read(), !apiKey.isEmpty else {
            throw TransactionParsingError.modelUnavailable(
                "Masukkan API key OpenRouter di Pengaturan untuk mengaktifkan pencatatan AI."
            )
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Atribusi opsional (docs quickstart) — bukan rahasia.
        request.setValue("https://github.com/akhnafal-aban/AkhnaFin", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AkhnaFin", forHTTPHeaderField: "X-Title")
        request.httpBody = try Self.body(
            model: model, messages: messages,
            schemaName: schemaName, schemaJSON: schemaJSON, structured: structured
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            clientLog.error("network gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed(
                "Tidak bisa menghubungi OpenRouter. Periksa koneksi internet."
            )
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.mapHTTPError(status: status, data: data)
        }

        let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded?.choices.first?.message.content, !content.isEmpty else {
            clientLog.error("respons tanpa content (status 200)")
            throw TransactionParsingError.parsingFailed("Respons model kosong. Coba lagi.")
        }
        return Data(content.utf8)
    }

    // MARK: - Request body

    private static func body(
        model: String,
        messages: [ORChatMessage],
        schemaName: String,
        schemaJSON: String,
        structured: Bool
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map(serialize(_:)),
        ]
        if structured {
            let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ]
            // Hanya route ke provider yang dukung structured outputs
            // (docs structured-outputs). Jangan set ini bila structured=false —
            // provider yang tak dukung json_schema akan ditolak semua → error.
            payload["provider"] = ["require_parameters": true]
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func serialize(_ message: ORChatMessage) -> [String: Any] {
        let content: [[String: Any]] = message.parts.map { part in
            switch part {
            case .text(let text):
                return ["type": "text", "text": text]
            case .image(let data):
                let dataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
                return ["type": "image_url", "image_url": ["url": dataURL]]
            }
        }
        return ["role": message.role, "content": content]
    }

    // MARK: - Error mapping (pesan siap-tampil)

    private static func mapHTTPError(status: Int, data: Data) -> TransactionParsingError {
        let apiMessage = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
        clientLog.error("HTTP \(status, privacy: .public): \(apiMessage ?? "-", privacy: .public)")
        switch status {
        case 401:
            return .modelUnavailable("API key OpenRouter tidak valid. Periksa kembali di Pengaturan.")
        case 402:
            return .modelUnavailable("Kredit OpenRouter habis. Isi ulang atau pakai model :free.")
        case 429:
            return .parsingFailed("Batas gratis OpenRouter tercapai. Tunggu sebentar lalu coba lagi.")
        default:
            return .parsingFailed(apiMessage ?? "OpenRouter mengembalikan kesalahan (HTTP \(status)).")
        }
    }

    // MARK: - Response DTO

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable { let message: String? }
        let error: APIError
    }
}
