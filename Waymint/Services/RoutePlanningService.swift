import Foundation
import MapKit

struct RoutePlanningService {
    func manualDurationMinutes(for segment: TravelSegment) -> Int {
        max(0, segment.plannedDurationMinutes)
    }

    func estimatedDurationMinutes(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> Int {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        request.transportType = mapKitTransportType(for: transportMode)

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
            return Self.fallbackDurationMinutes(from: start, to: destination, transportMode: transportMode)
        }
        return max(1, Int((route.expectedTravelTime / 60).rounded()))
    }

    static func fallbackDurationMinutes(
        from start: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) -> Int {
        let distance = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
        guard distance >= 20 else { return 1 }

        let metersPerSecond: Double
        switch transportMode {
        case .walking: metersPerSecond = 1.25
        case .bike: metersPerSecond = 4.2
        case .car, .taxi: metersPerSecond = 8.3
        case .publicTransport, .train: metersPerSecond = 6.0
        case .boat: metersPerSecond = 5.0
        case .other: metersPerSecond = 1.25
        }
        return max(1, Int((distance / metersPerSecond / 60).rounded(.up)))
    }

    private func mapKitTransportType(for mode: TransportMode) -> MKDirectionsTransportType {
        switch mode {
        case .walking:
            return .walking
        case .car, .taxi:
            return .automobile
        case .publicTransport, .train:
            return .transit
        case .bike, .boat, .other:
            return .any
        }
    }
}
