import Foundation
import CoreLocation
import OSLog
import ServiceInterfaces

private let locationLog = Logger(subsystem: "com.aban.AkhnaFin", category: "Location")

@MainActor
public final class CoreLocationService: NSObject, LocationCapturing {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private let timeout: Duration

    public init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func captureCurrent() async -> CapturedPlace? {
        if case .denied = manager.authorizationStatus {
            locationLog.info("lokasi: izin ditolak → nil")
            return nil
        }
        if case .restricted = manager.authorizationStatus { return nil }

        guard let location = await requestOneShot() else { return nil }
        let name = await reverseGeocode(location)
        return CapturedPlace(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            placeName: name
        )
    }

    // MARK: - One-shot dgn pagar waktu

    private func requestOneShot() async -> CLLocation? {
        await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: location)
    }

    private func reverseGeocode(_ location: CLLocation) async -> String {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return ""
        }
        return placemark.name ?? placemark.locality ?? placemark.subLocality ?? ""
    }
}

extension CoreLocationService: CLLocationManagerDelegate {
    public nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            finish(coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        Task { @MainActor in
            locationLog.error("lokasi gagal")
            finish(nil)
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                finish(nil)
            default:
                break  // .notDetermined: masih menunggu keputusan user
            }
        }
    }
}
