import Foundation

public protocol SpeechTranscribing: Sendable {
    func transcribeOnce() async throws -> String
}
