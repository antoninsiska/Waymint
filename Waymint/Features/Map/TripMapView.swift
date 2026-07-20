import MapKit
import SwiftData
import SwiftUI

struct TripMapView: View {
    let trip: TripPlan
    @State private var selectedStop: TripStop?
    @State private var routeLines: [TripMapRouteLine] = []

    private var stopsWithCoordinates: [TripStop] {
        trip.sortedStops.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var routeSignature: String {
        let stops = trip.sortedStops.map {
            "\($0.id.uuidString):\($0.sortIndex):\($0.latitude ?? 0):\($0.longitude ?? 0)"
        }
        let segments = trip.sortedTravelSegments.map {
            "\($0.fromStopID?.uuidString ?? "-"): \($0.toStopID?.uuidString ?? "-"): \($0.transportMode.rawValue)"
        }
        return (stops + segments).joined(separator: "|")
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates = stopsWithCoordinates.compactMap { stop -> CLLocationCoordinate2D? in
            guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        }

        let minLatitude = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? first.latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max(0.01, (maxLatitude - minLatitude) * 1.8)
        let longitudeDelta = max(0.01, (maxLongitude - minLongitude) * 1.8)

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    var body: some View {
        Group {
            if stopsWithCoordinates.isEmpty {
                EmptyStateView(
                    systemImage: "map",
                    title: "Mapa zatím nemá body",
                    message: "Najdi místo přes Apple Mapy při přidání zastávky a zobrazíme ho v pořadí plánu."
                )
            } else {
                ZStack(alignment: .bottom) {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(routeLines) { routeLine in
                            MapPolyline(routeLine.polyline)
                                .stroke(
                                    routeLine.isEstimated ? Color(red: 0.20, green: 0.28, blue: 0.24).opacity(0.62) : Color(red: 0.04, green: 0.16, blue: 0.11),
                                    style: StrokeStyle(lineWidth: routeLine.isEstimated ? 4 : 5, lineCap: .round, lineJoin: .round, dash: routeLine.isEstimated ? [7, 7] : [])
                                )
                        }

                        ForEach(Array(stopsWithCoordinates.enumerated()), id: \.element.id) { index, stop in
                            if let latitude = stop.latitude, let longitude = stop.longitude {
                                Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                                    Button {
                                        selectedStop = stop
                                    } label: {
                                        VStack(spacing: 5) {
                                            ZStack {
                                                Circle()
                                                    .fill(WaymintTheme.primaryGreen)
                                                    .frame(width: 32, height: 32)
                                                Text("\(index + 1)")
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(.white)
                                            }
                                            Text(stop.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(WaymintTheme.primaryText)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.thinMaterial, in: Capsule())
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }

                    HStack(spacing: 10) {
                        Label(WaymintLocalization.format("%d míst", stopsWithCoordinates.count), systemImage: "mappin.and.ellipse")
                        Spacer()
                        Text(LocalizedStringKey(routeLines.contains(where: \.isEstimated) ? "Odhad trasy" : "Apple Mapy"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WaymintTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .sheet(item: $selectedStop) { stop in
                    NavigationStack {
                        StopDetailView(stop: stop)
                    }
                }
                .task(id: routeSignature) {
                    routeLines = await TripMapRouteBuilder.routeLines(for: trip)
                }
            }
        }
    }

}

struct TripMapRouteLine: Identifiable {
    let id = UUID()
    let polyline: MKPolyline
    let isEstimated: Bool
}

enum TripMapRouteBuilder {
    static func routeLines(for trip: TripPlan, from: TripStop, to: TripStop) async -> [TripMapRouteLine] {
        guard let fromCoordinate = coordinate(for: from),
              let toCoordinate = coordinate(for: to) else {
            return []
        }
        let segment = trip.sortedTravelSegments.first { $0.toStopID == to.id }
        let mode = segment?.transportMode ?? .walking
        let cacheKey = routeCacheKey(from: fromCoordinate, to: toCoordinate, mode: mode)
        if let cached = RouteCacheService.shared.entry(for: cacheKey) {
            return [TripMapRouteLine(polyline: cached.polyline, isEstimated: cached.isEstimated)]
        }
        if let line = try? await routeLine(from: fromCoordinate, to: toCoordinate, transportMode: mode) {
            RouteCacheService.shared.store(polyline: line.polyline, isEstimated: false, for: cacheKey)
            return [line]
        }
        var coordinates = [fromCoordinate, toCoordinate]
        let fallback = MKPolyline(coordinates: &coordinates, count: coordinates.count)
        RouteCacheService.shared.store(polyline: fallback, isEstimated: true, for: cacheKey)
        return [TripMapRouteLine(polyline: fallback, isEstimated: true)]
    }

    static func routeLines(for trip: TripPlan) async -> [TripMapRouteLine] {
        let stops = trip.sortedStops
        guard stops.count > 1 else { return [] }

        var lines: [TripMapRouteLine] = []
        for index in 1..<stops.count {
            guard let from = coordinate(for: stops[index - 1]),
                  let to = coordinate(for: stops[index]) else {
                continue
            }

            let segment = trip.travelSegments?.first { $0.toStopID == stops[index].id }
            let mode = segment?.transportMode ?? .walking
            let cacheKey = routeCacheKey(from: from, to: to, mode: mode)
            if let cached = RouteCacheService.shared.entry(for: cacheKey) {
                lines.append(TripMapRouteLine(polyline: cached.polyline, isEstimated: cached.isEstimated))
                continue
            }
            if let routeLine = try? await routeLine(from: from, to: to, transportMode: mode) {
                lines.append(routeLine)
                RouteCacheService.shared.store(polyline: routeLine.polyline, isEstimated: false, for: cacheKey)
            } else {
                var coordinates = [from, to]
                let polyline = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                lines.append(TripMapRouteLine(polyline: polyline, isEstimated: true))
                RouteCacheService.shared.store(polyline: polyline, isEstimated: true, for: cacheKey)
            }
        }
        return lines
    }

    private static func routeCacheKey(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: TransportMode) -> String {
        "\(from.latitude.rounded(toPlaces: 5)),\(from.longitude.rounded(toPlaces: 5))-\(to.latitude.rounded(toPlaces: 5)),\(to.longitude.rounded(toPlaces: 5))-\(mode.rawValue)"
    }

    private static func coordinate(for stop: TripStop) -> CLLocationCoordinate2D? {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func routeLine(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transportMode: TransportMode
    ) async throws -> TripMapRouteLine {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = transportMode.mapKitTransportType
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw MKError(.directionsNotFound)
        }
        return TripMapRouteLine(polyline: route.polyline, isEstimated: false)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension TransportMode {
    var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .walking:
            return .walking
        case .publicTransport, .train:
            return .transit
        case .car, .taxi:
            return .automobile
        default:
            return .any
        }
    }
}

#Preview {
    TripMapView(trip: TripPlan(title: "Centrum"))
        .modelContainer(PreviewData.container())
}
