import CoreLocation

/// One-shot location lookup for the "konumumu paylaş" button.
///
/// Deliberately minimal: no continuous updates, no stored state, nothing
/// observable. The button asks once, gets a coordinate or `nil`, and is done —
/// the app has no other use for location, so there is nothing to keep running.
///
/// Requires `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in the build
/// settings; the project generates its Info.plist (`GENERATE_INFOPLIST_FILE`),
/// so there is no plist file to add it to.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    /// Resumed by `didUpdateLocations` / `didFailWithError`.
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    /// Resumed by `locationManagerDidChangeAuthorization` — only ever set while
    /// the permission prompt is on screen.
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Asks for permission if it has not been decided yet, then for a single
    /// fix. Returns `nil` if permission is refused or the fix fails — the
    /// caller falls back to sending the message without a pin.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }

        // Guard against a second tap while a fix is already in flight: the
        // delegate can only resume one continuation, and dropping the earlier
        // one would leak its task forever.
        guard locationContinuation == nil else { return nil }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // This also fires once on delegate assignment, still reporting
            // `.notDetermined`. If that late delivery lands while the prompt is
            // on screen it must not count as her answer — otherwise the caller
            // sees "no permission" and sends the message without a pin before
            // she has even chosen.
            guard status != .notDetermined else { return }
            authorizationContinuation?.resume()
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            locationContinuation?.resume(returning: coordinate)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}
