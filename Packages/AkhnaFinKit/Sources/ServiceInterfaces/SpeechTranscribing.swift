import Foundation

/// Transkripsi ucapan menjadi teks (implementasi: `SpeechAnalyzer`/`SpeechTranscriber`, Fase 3).
///
/// API minimal untuk saat ini; akan diperluas dengan streaming transkrip live pada Fase 3.
public protocol SpeechTranscribing: Sendable {
    /// Rekam satu segmen ucapan lalu kembalikan transkrip finalnya.
    func transcribeOnce() async throws -> String
}
