import Combine
import CoreLocation
import Foundation

@MainActor
final class ActiveTripLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()
    private var didRequestAlwaysAuthorization = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        configureBackgroundUpdatesIfSupported()
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.startUpdatingLocation()
            requestAlwaysAuthorizationIfNeeded()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = WaymintLocalization.text("Poloha není povolená. GPS korekci můžeš zapnout v Nastavení systému.")
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func configure(lowPower: Bool) {
        manager.desiredAccuracy = lowPower ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyBest
        manager.distanceFilter = lowPower ? 100 : 25
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            errorMessage = nil
            manager.startUpdatingLocation()
            requestAlwaysAuthorizationIfNeeded()
        } else if manager.authorizationStatus == .authorizedAlways {
            errorMessage = nil
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newest = locations.last,
              newest.horizontalAccuracy >= 0,
              newest.horizontalAccuracy <= 100,
              abs(newest.timestamp.timeIntervalSinceNow) < 30 else {
            return
        }
        location = newest
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        errorMessage = WaymintLocalization.format("Polohu se nepodařilo aktualizovat: %@", error.localizedDescription)
    }

    private func configureBackgroundUpdatesIfSupported() {
#if targetEnvironment(simulator)
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
#else
        let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let supportsBackgroundLocation = backgroundModes.contains("location")
        manager.allowsBackgroundLocationUpdates = supportsBackgroundLocation
        manager.showsBackgroundLocationIndicator = supportsBackgroundLocation
#endif
    }

    private func requestAlwaysAuthorizationIfNeeded() {
        guard !didRequestAlwaysAuthorization else { return }
        didRequestAlwaysAuthorization = true
        manager.requestAlwaysAuthorization()
    }
}
