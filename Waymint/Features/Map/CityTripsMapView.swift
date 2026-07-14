import MapKit
import SwiftData
import SwiftUI

struct CityTripsMapView: View {
    let city: CityPlan

    @State private var selectedStop: TripStop?
    @State private var routeGroups: [CityTripRouteGroup] = []

    private var trips: [TripPlan] {
        city.sortedTripPlans.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.date < rhs.date
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    private var mappedStops: [CityMappedStop] {
        trips.enumerated().flatMap { tripIndex, trip in
            trip.sortedStops.enumerated().compactMap { stopIndex, stop in
                guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
                return CityMappedStop(
                    trip: trip,
                    tripIndex: tripIndex,
                    stop: stop,
                    stopIndex: stopIndex,
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
            }
        }
    }

    private var mapRegion: MKCoordinateRegion {
        guard let first = mappedStops.first?.coordinate else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        let coordinates = mappedStops.map(\.coordinate)
        let minLatitude = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? first.latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.02, (maxLatitude - minLatitude) * 1.9),
                longitudeDelta: max(0.02, (maxLongitude - minLongitude) * 1.9)
            )
        )
    }

    var body: some View {
        Group {
            if mappedStops.isEmpty {
                EmptyStateView(
                    systemImage: "map",
                    title: "Mapa města je prázdná",
                    message: "Přidej k zastávkám místa přes Apple Mapy nebo ruční bod na mapě."
                )
            } else {
                ZStack(alignment: .bottom) {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(routeGroups) { group in
                            ForEach(group.lines) { line in
                                MapPolyline(line.polyline)
                                    .stroke(
                                        group.color.opacity(line.isEstimated ? 0.52 : 0.92),
                                        style: StrokeStyle(
                                            lineWidth: line.isEstimated ? 3.5 : 5,
                                            lineCap: .round,
                                            lineJoin: .round,
                                            dash: line.isEstimated ? [7, 7] : []
                                        )
                                    )
                            }
                        }

                        ForEach(mappedStops) { item in
                            Annotation("", coordinate: item.coordinate) {
                                Button {
                                    selectedStop = item.stop
                                } label: {
                                    VStack(spacing: 5) {
                                        ZStack {
                                            Circle()
                                                .fill(cityTripAccentColor(item.tripIndex))
                                                .frame(width: 34, height: 34)
                                            Text("\(item.stopIndex + 1)")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                        Text(item.stop.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(WaymintTheme.primaryText)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.72)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.thinMaterial, in: Capsule())
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .mapControls {
                        MapCompass()
                        MapScaleView()
                    }

                    CityMapLegend(trips: trips, routeGroups: routeGroups)
                        .padding(12)
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Mapa města")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selectedStop) { stop in
                    NavigationStack {
                        StopDetailView(stop: stop)
                    }
                }
                .task(id: city.updatedAt) {
                    routeGroups = await buildRouteGroups()
                }
            }
        }
    }

    private func buildRouteGroups() async -> [CityTripRouteGroup] {
        var groups: [CityTripRouteGroup] = []
        for (index, trip) in trips.enumerated() {
            let lines = await TripMapRouteBuilder.routeLines(for: trip)
            if !lines.isEmpty {
                groups.append(CityTripRouteGroup(trip: trip, color: cityTripLineColor(index), lines: lines))
            }
        }
        return groups
    }
}

private struct CityMappedStop: Identifiable {
    let id = UUID()
    let trip: TripPlan
    let tripIndex: Int
    let stop: TripStop
    let stopIndex: Int
    let coordinate: CLLocationCoordinate2D
}

private struct CityTripRouteGroup: Identifiable {
    let id = UUID()
    let trip: TripPlan
    let color: Color
    let lines: [TripMapRouteLine]
}

private struct CityMapLegend: View {
    let trips: [TripPlan]
    let routeGroups: [CityTripRouteGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(trips.count) cest", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Spacer()
                Text(routeGroups.contains { $0.lines.contains(where: \.isEstimated) } ? "Část odhadnuta" : "Apple Mapy")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(WaymintTheme.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        Label {
                            Text(trip.title)
                                .lineLimit(1)
                        } icon: {
                            Circle()
                                .fill(cityTripAccentColor(index))
                                .frame(width: 9, height: 9)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
    }
}

private func cityTripAccentColor(_ index: Int) -> Color {
    let colors: [Color] = [
        WaymintTheme.primaryGreen,
        Color(red: 0.20, green: 0.42, blue: 0.82),
        Color(red: 0.66, green: 0.30, blue: 0.74),
        Color(red: 0.76, green: 0.35, blue: 0.18),
        Color(red: 0.12, green: 0.52, blue: 0.58)
    ]
    return colors[index % colors.count]
}

private func cityTripLineColor(_ index: Int) -> Color {
    let colors: [Color] = [
        Color(red: 0.04, green: 0.16, blue: 0.11),
        Color(red: 0.06, green: 0.18, blue: 0.44),
        Color(red: 0.31, green: 0.12, blue: 0.38),
        Color(red: 0.39, green: 0.16, blue: 0.07),
        Color(red: 0.03, green: 0.24, blue: 0.27)
    ]
    return colors[index % colors.count]
}

#Preview {
    NavigationStack {
        CityTripsMapView(city: CityPlan(name: "Praha", country: "Česko"))
    }
    .modelContainer(PreviewData.container())
}
