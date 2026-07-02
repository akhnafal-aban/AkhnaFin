import Foundation

/// Lokasi yang ditangkap otomatis-senyap saat sebuah transaksi di-commit.
public struct CapturedPlace: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    /// Nama tempat hasil reverse-geocode (bisa kosong bila geocoding gagal).
    public var placeName: String

    public init(latitude: Double, longitude: Double, placeName: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }
}
