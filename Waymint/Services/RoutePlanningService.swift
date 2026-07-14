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
            return 0
        }
        return max(1, Int((route.expectedTravelTime / 60).rounded()))
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
