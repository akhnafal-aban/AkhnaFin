import Foundation

/// Penangkap lokasi palsu untuk unit test & SwiftUI Preview.
public struct MockLocationCapturer: LocationCapturing {
    public var place: CapturedPlace?

    public init(
        place: CapturedPlace? = CapturedPlace(
            latitude: -6.1754,
            longitude: 106.8272,
            placeName: "Jakarta"
        )
    ) {
        self.place = place
    }

    public func captureCurrent() async -> CapturedPlace? {
        place
    }
}
