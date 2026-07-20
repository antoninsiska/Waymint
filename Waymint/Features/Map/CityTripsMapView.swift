import MapKit
import SwiftData
import SwiftUI

struct CityTripsMapView: View {
    let city: CityPlan

    @State private var selectedStop: TripStop?
    @State private var routeGroups: [CityTripRouteGroup] = []
    @State private var selectedTripID: UUID?
    @State private var cameraPosition = MapCameraPosition.automatic
    @State private var showingStopDetail = false
    @State private var isTripPickerExpanded = true

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

    private var visibleStops: [CityMappedStop] {
        guard let selectedTripID else { return mappedStops }
        return mappedStops.filter { $0.trip.id == selectedTripID }
    }

    private var visibleRouteGroups: [CityTripRouteGroup] {
        guard let selectedTripID else { return routeGroups }
        return routeGroups.filter { $0.trip.id == selectedTripID }
    }

    private var mapRegion: MKCoordinateRegion {
        region(for: visibleStops)
    }

    private var tripIssues: [CityMapTripIssue] {
        trips.compactMap { trip in
            let missingLocations = trip.sortedStops.filter { !$0.coordinateIsValid }.count
            let invalidTransfers = trip.sortedStops.dropFirst().filter { stop in
                guard let segment = trip.sortedTravelSegments.first(where: { $0.toStopID == stop.id }) else {
                    return true
                }
                return segment.plannedDurationMinutes <= 0
            }.count
            guard missingLocations + invalidTransfers > 0 else { return nil }
            return CityMapTripIssue(
                trip: trip,
                missingLocationCount: missingLocations,
                invalidTransferCount: invalidTransfers
            )
        }
    }

    private func region(for stops: [CityMappedStop]) -> MKCoordinateRegion {
        guard let first = stops.first?.coordinate else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        let coordinates = stops.map(\.coordinate)
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
                    Map(position: $cameraPosition) {
                        ForEach(visibleRouteGroups) { group in
                            ForEach(group.lines) { line in
                                MapPolyline(line.polyline)
                                    .stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
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

                        ForEach(visibleStops) { item in
                            Annotation("", coordinate: item.coordinate) {
                                Button {
                                    withAnimation(.snappy) {
                                        selectedStop = item.stop
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(cityTripAccentColor(item.tripIndex))
                                                .frame(width: selectedStop?.id == item.stop.id ? 40 : 32, height: selectedStop?.id == item.stop.id ? 40 : 32)
                                                .overlay { Circle().stroke(.white, lineWidth: 3) }
                                                .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                                            Text("\(item.stopIndex + 1)")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                        if selectedStop?.id == item.stop.id {
                                            Text(item.stop.title)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(WaymintTheme.primaryText)
                                                .lineLimit(1)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(.regularMaterial, in: Capsule())
                                        }
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
                        MapUserLocationButton()
                    }

                    VStack(spacing: 10) {
                        HStack {
                            CityMapSummaryPill(
                                tripCount: selectedTripID == nil ? trips.count : 1,
                                stopCount: visibleStops.count,
                                hasEstimate: visibleRouteGroups.contains { $0.lines.contains(where: \.isEstimated) }
                            )
                            if let firstIssue = tripIssues.first {
                                Button {
                                    withAnimation(.snappy) {
                                        selectedTripID = firstIssue.trip.id
                                        isTripPickerExpanded = true
                                    }
                                } label: {
                                    Label("\(tripIssues.reduce(0) { $0 + $1.totalCount })", systemImage: "wrench.and.screwdriver.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(WaymintTheme.warning)
                                        .padding(.horizontal, 10)
                                        .frame(height: 42)
                                        .background(.regularMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Problémy k opravě")
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeInOut) {
                                    cameraPosition = .region(mapRegion)
                                }
                            } label: {
                                Image(systemName: "scope")
                                    .font(.headline)
                                    .foregroundStyle(WaymintTheme.darkGreen)
                                    .frame(width: 42, height: 42)
                                    .background(.regularMaterial, in: Circle())
                                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                            }
                            .accessibilityLabel("Zobrazit vybrané cesty")
                        }

                        Spacer()

                        if let selectedStop {
                            CityMapSelectedStopCard(stop: selectedStop) {
                                showingStopDetail = true
                            }
                        }

                        CityMapLegend(
                            trips: trips,
                            issues: tripIssues,
                            selectedTripID: $selectedTripID,
                            isExpanded: $isTripPickerExpanded
                        )
                    }
                    .padding(12)
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Mapa města")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingStopDetail) {
                    NavigationStack {
                        if let selectedStop {
                            StopDetailView(stop: selectedStop)
                        }
                    }
                }
                .task(id: city.updatedAt) {
                    routeGroups = await buildRouteGroups()
                    cameraPosition = .region(mapRegion)
                }
                .onChange(of: selectedTripID) { _, _ in
                    selectedStop = nil
                    withAnimation(.easeInOut) {
                        cameraPosition = .region(mapRegion)
                    }
                }
            }
        }
    }

    private func buildRouteGroups() async -> [CityTripRouteGroup] {
        var groups: [CityTripRouteGroup] = []
        for (index, trip) in trips.enumerated() {
            let lines = await TripMapRouteBuilder.routeLines(for: trip)
            if !lines.isEmpty {
                groups.append(CityTripRouteGroup(
                    trip: trip,
                    color: cityTripLineColor(index),
                    lines: lines
                ))
            }
        }
        return groups
    }
}

private struct CityMappedStop: Identifiable {
    var id: UUID { stop.id }
    let trip: TripPlan
    let tripIndex: Int
    let stop: TripStop
    let stopIndex: Int
    let coordinate: CLLocationCoordinate2D
}

private struct CityTripRouteGroup: Identifiable {
    var id: UUID { trip.id }
    let trip: TripPlan
    let color: Color
    let lines: [TripMapRouteLine]
}

private struct CityMapTripIssue: Identifiable {
    var id: UUID { trip.id }
    let trip: TripPlan
    let missingLocationCount: Int
    let invalidTransferCount: Int
    var totalCount: Int { missingLocationCount + invalidTransferCount }
}

private struct CityMapLegend: View {
    let trips: [TripPlan]
    let issues: [CityMapTripIssue]
    @Binding var selectedTripID: UUID?
    @Binding var isExpanded: Bool

    private var selectedTrip: TripPlan? {
        trips.first { $0.id == selectedTripID }
    }

    private var selectedIssue: CityMapTripIssue? {
        issues.first { $0.trip.id == selectedTripID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 13 : 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(WaymintTheme.primaryGreen)
                        .frame(width: 34, height: 34)
                        .background(WaymintTheme.lightGreen, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cesty na mapě")
                            .font(.subheadline.weight(.bold))
                        Text(selectedTrip?.title ?? WaymintLocalization.format("Všechny cesty (%d)", trips.count))
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WaymintTheme.primaryGreen)
                        .frame(width: 34, height: 34)
                        .background(WaymintTheme.lightGreen, in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Skrýt výběr cest" : "Zobrazit výběr cest")

            if isExpanded {
                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        Button {
                            selectedTripID = nil
                        } label: {
                            Label("Všechny", systemImage: "square.stack.3d.up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedTripID == nil ? .white : WaymintTheme.primaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(selectedTripID == nil ? WaymintTheme.primaryGreen : WaymintTheme.elevatedSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                            Button {
                                selectedTripID = trip.id
                            } label: {
                                HStack(spacing: 9) {
                                    Circle()
                                        .fill(selectedTripID == trip.id ? .white : cityTripAccentColor(index))
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trip.title)
                                            .font(.subheadline.weight(.bold))
                                            .lineLimit(1)
                                        Text(trip.date.waymintDate)
                                            .font(.caption)
                                            .opacity(0.78)
                                    }
                                }
                                .foregroundStyle(selectedTripID == trip.id ? .white : WaymintTheme.primaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(selectedTripID == trip.id ? cityTripAccentColor(index) : WaymintTheme.elevatedSurface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedTrip {
                    if let selectedIssue {
                        NavigationLink {
                            TripOverviewView(trip: selectedTrip)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundStyle(WaymintTheme.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cesta vyžaduje opravu")
                                        .font(.subheadline.weight(.bold))
                                    Text(cityMapIssueDescription(selectedIssue))
                                        .font(.caption)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                }
                                Spacer()
                                Text("Opravit")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WaymintTheme.warning)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(11)
                            .background(WaymintTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        TripOverviewView(trip: selectedTrip)
                    } label: {
                        HStack(spacing: 10) {
                            Label(selectedTrip.scheduleLabel, systemImage: "clock")
                            Spacer()
                            Text("Otevřít přehled")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WaymintTheme.primaryGreen)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(WaymintTheme.lightGreen.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(isExpanded ? 15 : 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}

private struct CityMapSummaryPill: View {
    let tripCount: Int
    let stopCount: Int
    let hasEstimate: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(WaymintLocalization.format("%d cest", tripCount), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            Divider().frame(height: 14)
            Label(WaymintLocalization.format("%d míst", stopCount), systemImage: "mappin.and.ellipse")
            if hasEstimate {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(WaymintTheme.warning)
                    .accessibilityLabel("Část trasy je odhadnutá")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(WaymintTheme.primaryText)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

private struct CityMapSelectedStopCard: View {
    let stop: TripStop
    let openDetail: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stop.stopType.systemImage)
                .font(.title2)
                .foregroundStyle(WaymintTheme.primaryGreen)
                .frame(width: 40, height: 40)
                .background(WaymintTheme.lightGreen, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.tripPlan?.title ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WaymintTheme.secondaryText)
                    .lineLimit(1)
                Text(stop.title)
                    .font(.headline)
                    .foregroundStyle(WaymintTheme.primaryText)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: openDetail) {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 38)
                    .background(WaymintTheme.lightGreen, in: Circle())
            }
            .accessibilityLabel("Detail místa")
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
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

private func cityMapIssueDescription(_ issue: CityMapTripIssue) -> String {
    if issue.missingLocationCount > 0, issue.invalidTransferCount > 0 {
        return WaymintLocalization.format(
            "%d míst bez polohy · %d neplatných přesunů",
            issue.missingLocationCount,
            issue.invalidTransferCount
        )
    }
    if issue.missingLocationCount > 0 {
        return WaymintLocalization.format("%d míst bez polohy", issue.missingLocationCount)
    }
    return WaymintLocalization.format("%d neplatných přesunů", issue.invalidTransferCount)
}

#Preview {
    NavigationStack {
        CityTripsMapView(city: CityPlan(name: "Praha", country: "Česko"))
    }
    .modelContainer(PreviewData.container())
}
