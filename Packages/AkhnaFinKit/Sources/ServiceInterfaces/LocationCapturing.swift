import Foundation

public protocol LocationCapturing: Sendable {
    func captureCurrent() async -> CapturedPlace?
}
