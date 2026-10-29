import Foundation
import OSLog
import ServiceInterfaces

private let clientLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Inference")

public enum InferenceModel {
    public static let glm53 = "zai-org/GLM-5.3"
    public static let defaultReasoningEffort = "max"
}

public struct InferenceClient: Sendable {
    private let keyStore: any APIKeyStoring
    private let session: URLSession
    private static let endpoint = URL(string: "https://api.inference.wandb.ai/v1/chat/completions")!

    public init(keyStore: any APIKeyStoring, session: URLSession = .shared) {
        self.keyStore = keyStore
        self.session = session
    }

    public func complete(
        model: String = InferenceModel.glm53,
        reasoningEffort: String = InferenceModel.defaultReasoningEffort,
        system: String,
        user: String
    ) async throws -> String {
        guard let apiKey = keyStore.read(), !apiKey.isEmpty else {
            throw TransactionParsingError.modelUnavailable(
                "Masukkan API key W&B di Pengaturan untuk mengaktifkan pencatatan AI."
            )
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try Self.body(model: model, reasoningEffort: reasoningEffort, system: system, user: user)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            clientLog.error("network gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed(
                "Tidak bisa menghubungi server AI. Periksa koneksi internet."
            )
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.mapHTTPError(status: status, data: data)
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            clientLog.error("decode response gagal: \(String(describing: error), privacy: .public)")
            throw TransactionParsingError.parsingFailed("Respons model tidak bisa dibaca. Coba lagi.")
        }
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            clientLog.error("respons tanpa content (status 200)")
            throw TransactionParsingError.parsingFailed("Respons model kosong. Coba lagi.")
        }
        return content
    }

    private static func body(model: String, reasoningEffort: String, system: String, user: String) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "reasoning_effort": reasoningEffort,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func mapHTTPError(status: Int, data: Data) -> TransactionParsingError {
        let apiMessage = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message
        clientLog.error("HTTP \(status, privacy: .public): \(apiMessage ?? "-", privacy: .public)")
        switch status {
        case 401:
            return .modelUnavailable("API key W&B tidak valid. Periksa kembali di Pengaturan.")
        case 429:
            return .parsingFailed("Batas permintaan tercapai. Tunggu sebentar lalu coba lagi.")
        default:
            return .parsingFailed(apiMessage ?? "Server AI mengembalikan kesalahan (HTTP \(status)).")
        }
    }

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