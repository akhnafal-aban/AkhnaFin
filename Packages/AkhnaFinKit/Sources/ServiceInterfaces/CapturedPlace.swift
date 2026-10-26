import Foundation

public struct CapturedPlace: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var placeName: String

    public init(latitude: Double, longitude: Double, placeName: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }
}
