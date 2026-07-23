import Foundation
import OSLog

private let catalogLog = Logger(subsystem: "com.aban.AkhnaFin", category: "OpenRouter")

/// Satu model dari katalog publik OpenRouter — bahan layar pilih model.
public struct CatalogModel: Identifiable, Sendable, Equatable {
    public let slug: String
    public let name: String
    public let acceptsImage: Bool
    public let supportsStructured: Bool
    public let isFree: Bool
    /// Harga per 1 JUTA token (prompt/completion) — tampilan; 0 utk :free.
    public let promptPricePerMillion: Double
    public let completionPricePerMillion: Double

    public var id: String { slug }
}

/// Katalog model dari `GET /api/v1/models` — endpoint PUBLIK (tanpa API key,
/// terverifikasi lewat curl tanpa header auth saat riset PLAN-006/007).
/// Cache in-memory per proses; refresh manual dari UI.
public actor OpenRouterModelCatalog {
    private let session: URLSession
    private var cached: [CatalogModel]?
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/models")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Daftar model, urut nama. `forceRefresh` mengabaikan cache.
    public func models(forceRefresh: Bool = false) async throws -> [CatalogModel] {
        if !forceRefresh, let cached { return cached }
        let (data, response) = try await session.data(from: Self.endpoint)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data
            .map(Self.map(_:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cached = models
        catalogLog.info("katalog dimuat: \(models.count) model")
        return models
    }

    private static func map(_ raw: RawModel) -> CatalogModel {
        let supported = raw.supportedParameters ?? []
        let prompt = Double(raw.pricing?.prompt ?? "0") ?? 0
        let completion = Double(raw.pricing?.completion ?? "0") ?? 0
        return CatalogModel(
            slug: raw.id,
            name: raw.name ?? raw.id,
            acceptsImage: raw.architecture?.inputModalities?.contains("image") ?? false,
            supportsStructured: supported.contains("structured_outputs")
                || supported.contains("response_format"),
            isFree: raw.id.hasSuffix(":free") || (prompt == 0 && completion == 0),
            promptPricePerMillion: prompt * 1_000_000,
            completionPricePerMillion: completion * 1_000_000
        )
    }

    // MARK: - DTO respons /models

    private struct ModelsResponse: Decodable {
        let data: [RawModel]
    }

    private struct RawModel: Decodable {
        let id: String
        let name: String?
        let architecture: Architecture?
        let pricing: Pricing?
        let supportedParameters: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, architecture, pricing
            case supportedParameters = "supported_parameters"
        }

        struct Architecture: Decodable {
            let inputModalities: [String]?

            enum CodingKeys: String, CodingKey {
                case inputModalities = "input_modalities"
            }
        }

        struct Pricing: Decodable {
            let prompt: String?
            let completion: String?
        }
    }
}
