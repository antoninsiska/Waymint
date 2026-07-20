import MapKit
import SwiftData
import SwiftUI

struct DataHealthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CityPlan.sortIndex) private var cities: [CityPlan]
    @State private var repairMessage: String?
    @State private var isRepairing = false

    private var issues: [WaymintDataIssue] {
        WaymintDataDiagnostics.issues(in: cities)
    }

    private var repairableIssues: [WaymintDataIssue] { issues.filter(\.isRepairable) }
    private var manualIssues: [WaymintDataIssue] { issues.filter { !$0.isRepairable } }

    var body: some View {
        NavigationStack {
            List {
                if issues.isEmpty {
                    ContentUnavailableView("Data jsou v pořádku", systemImage: "checkmark.shield.fill", description: Text("Nenašli jsme chybějící GPS ani poškozenou časovou osu."))
                } else {
                    if !repairableIssues.isEmpty {
                    Section("Lze opravit automaticky") {
                        ForEach(repairableIssues) { issue in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.title).font(.headline)
                                    Text(issue.detail).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: issue.systemImage).foregroundStyle(issue.isRepairable ? WaymintTheme.warning : WaymintTheme.secondaryText)
                            }
                        }
                    }
                    }
                    if !manualIssues.isEmpty {
                        Section("Vyžaduje ruční doplnění") {
                            ForEach(manualIssues) { issue in
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(issue.title).font(.headline)
                                        Text(issue.detail).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                                    }
                                } icon: { Image(systemName: issue.systemImage).foregroundStyle(WaymintTheme.secondaryText) }
                            }
                        }
                    }
                    Section {
                        Button {
                            let count = repairableIssues.count
                            isRepairing = true
                            Task {
                                await WaymintDataDiagnostics.repair(cities)
                                try? modelContext.save()
                                repairMessage = count == 0
                                    ? WaymintLocalization.text("Nebyly nalezeny žádné automaticky opravitelné problémy.")
                                    : WaymintLocalization.format(
                                        "Opraveno problémů: %@. Nulové přesuny byly znovu spočítány přes Apple Mapy. Položky bez GPS zůstávají, dokud u nich nevybereš místo v Apple Mapách.",
                                        String(count)
                                    )
                                isRepairing = false
                            }
                        } label: {
                            if isRepairing {
                                Label("Počítám přesuny…", systemImage: "map")
                            } else {
                                Label("Opravit časové osy a propojení", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .disabled(repairableIssues.isEmpty || isRepairing)
                    } footer: {
                        Text("Chybějící GPS je potřeba doplnit ručně přes Apple Mapy. Automatická oprava nesmaže žádná místa.")
                    }
                }
            }
            .navigationTitle("Kontrola dat")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { dismiss() } } }
            .alert("Výsledek opravy", isPresented: Binding(get: { repairMessage != nil }, set: { if !$0 { repairMessage = nil } })) {
                Button("OK", role: .cancel) { repairMessage = nil }
            } message: { Text(repairMessage ?? "") }
        }
    }
}

struct WaymintDataIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let isRepairable: Bool
}

struct TripReadinessIssue: Identifiable {
    enum Severity { case warning, blocking }
    let id = UUID()
    let title: String
    let detail: String
    let systemImage: String
    let severity: Severity
}

enum TripReadinessChecker {
    static func issues(for trip: TripPlan) -> [TripReadinessIssue] {
        var issues: [TripReadinessIssue] = []
        let stops = trip.sortedStops
        if stops.isEmpty {
            issues.append(.init(title: WaymintLocalization.text("Cesta nemá zastávky"), detail: WaymintLocalization.text("Před spuštěním přidej alespoň jeden bod."), systemImage: "list.bullet", severity: .blocking))
        }
        for stop in stops where !stop.coordinateIsValid {
            issues.append(.init(title: WaymintLocalization.text("Chybí poloha"), detail: stop.title, systemImage: "location.slash", severity: .blocking))
        }
        if stops.count > 1 {
            for index in 1..<stops.count {
                let previous = stops[index - 1]
                let stop = stops[index]
                let segment = trip.sortedTravelSegments.first { $0.toStopID == stop.id }
                if segment == nil || (segment?.plannedDurationMinutes ?? 0) <= 0 {
                    issues.append(.init(title: WaymintLocalization.text("Chybí platný přesun"), detail: "\(previous.title) → \(stop.title)", systemImage: "arrow.triangle.swap", severity: .blocking))
                }
                if stop.plannedArrival < previous.plannedDeparture {
                    issues.append(.init(title: WaymintLocalization.text("Překrývající se časy"), detail: "\(previous.title) → \(stop.title)", systemImage: "clock.badge.exclamationmark", severity: .blocking))
                }
                if let segment, segment.bufferMinutes < 5, trip.hasFixedStartTime {
                    issues.append(.init(title: WaymintLocalization.text("Těsný harmonogram"), detail: WaymintLocalization.format("%@ → %@ nemá alespoň 5 minut rezervy.", previous.title, stop.title), systemImage: "hourglass", severity: .warning))
                }
            }
        }
        for ticket in trip.allTickets {
            if let path = ticket.localFilePath, !path.isEmpty,
               !FileManager.default.fileExists(atPath: path) {
                issues.append(.init(title: WaymintLocalization.text("Chybí soubor vstupenky"), detail: ticket.title, systemImage: "ticket", severity: .blocking))
            }
        }
        return issues
    }

    static func isReady(_ trip: TripPlan) -> Bool {
        !issues(for: trip).contains { $0.severity == .blocking }
    }
}

@MainActor
enum WaymintDataDiagnostics {
    static func issues(in cities: [CityPlan]) -> [WaymintDataIssue] {
        var result: [WaymintDataIssue] = []
        for city in cities {
            for trip in city.sortedTripPlans {
                let stops = trip.sortedStops
                for stop in stops where !stop.coordinateIsValid {
                    result.append(.init(title: WaymintLocalization.format("%@ nemá GPS", stop.title), detail: "\(city.name) · \(trip.title)", systemImage: "location.slash", isRepairable: false))
                }
                if trip.sortedTravelSegments.filter({ $0.fromStopID != nil && $0.toStopID != nil }).count != max(0, stops.count - 1) {
                    result.append(.init(title: WaymintLocalization.text("Nepropojené přesuny"), detail: "\(city.name) · \(trip.title)", systemImage: "link.badge.plus", isRepairable: true))
                }
                if trip.sortedTravelSegments.contains(where: {
                    $0.fromStopID != nil && $0.toStopID != nil && $0.plannedDurationMinutes <= 0
                }) {
                    result.append(.init(title: WaymintLocalization.text("Nulová délka přesunu"), detail: "\(city.name) · \(trip.title)", systemImage: "clock.badge.exclamationmark", isRepairable: true))
                }
                if stops.count > 1 {
                    for index in 1..<stops.count where stops[index].plannedArrival < stops[index - 1].plannedDeparture {
                        result.append(.init(title: WaymintLocalization.text("Překrývající se program"), detail: "\(stops[index - 1].title) → \(stops[index].title)", systemImage: "clock.badge.exclamationmark", isRepairable: true))
                    }
                }
            }
        }
        return result
    }

    static func repair(_ cities: [CityPlan]) async {
        let calculator = ScheduleCalculator()
        let routePlanner = RoutePlanningService()
        for trip in cities.flatMap(\.sortedTripPlans) {
            let stops = trip.sortedStops
            while trip.sortedTravelSegments.count < max(0, stops.count - 1) {
                let index = trip.sortedTravelSegments.count
                let from = stops[index]
                let to = stops[index + 1]
                let inferredMinutes = max(1, Int(to.plannedArrival.timeIntervalSince(from.plannedDeparture) / 60))
                trip.addTravelSegment(TravelSegment(
                    plannedDurationMinutes: inferredMinutes,
                    plannedDeparture: from.plannedDeparture,
                    fromStopID: from.id,
                    toStopID: to.id,
                    sortIndex: index
                ))
            }

            calculator.reconnectAndRecalculate(trip)

            for (index, segment) in trip.sortedTravelSegments.enumerated()
            where index + 1 < stops.count && segment.plannedDurationMinutes <= 0 {
                let from = stops[index]
                let to = stops[index + 1]
                let scheduleGap = Int(to.plannedArrival.timeIntervalSince(from.plannedDeparture) / 60)

                if scheduleGap > 0 {
                    segment.plannedDurationMinutes = scheduleGap
                } else if let start = coordinate(for: from), let destination = coordinate(for: to) {
                    segment.plannedDurationMinutes = (try? await routePlanner.estimatedDurationMinutes(
                        from: start,
                        to: destination,
                        transportMode: segment.transportMode
                    )) ?? RoutePlanningService.fallbackDurationMinutes(
                        from: start,
                        to: destination,
                        transportMode: segment.transportMode
                    )
                } else {
                    segment.plannedDurationMinutes = 1
                }
                segment.bufferMinutes = max(0, segment.bufferMinutes)
            }
            calculator.reconnectAndRecalculate(trip)
        }
    }

    private static func coordinate(for stop: TripStop) -> CLLocationCoordinate2D? {
        guard stop.coordinateIsValid,
              let latitude = stop.latitude,
              let longitude = stop.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
