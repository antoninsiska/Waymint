import MapKit
import SwiftUI

struct TripAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: TripPlan

    @State private var preparingOffline = false
    @State private var assistantMessage: String?
    @State private var confirmingShortPlan = false

    private var issues: [TripReadinessIssue] { TripReadinessChecker.issues(for: trip) }
    private var optionalStops: [TripStop] { trip.sortedStops.filter { !$0.isRequired && $0.status == .planned } }
    private var missingGPSCount: Int { trip.sortedStops.filter { !$0.coordinateIsValid }.count }
    private var fixedEventCount: Int { trip.sortedStops.filter(\.isTimeAnchor).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(assistantHeadline).font(.headline)
                            Text(assistantDetail).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                        }
                    } icon: {
                        Image(systemName: assistantIcon)
                            .foregroundStyle(issues.isEmpty ? WaymintTheme.success : WaymintTheme.warning)
                    }
                }

                Section("Příprava") {
                    assistantRow("Offline data", value: trip.offlinePreparedAt == nil ? "Nejsou připravená" : "Připravená", icon: "arrow.down.circle")
                    assistantRow("Vstupenky", value: "\(trip.totalTicketCount)", icon: "ticket")
                    assistantRow("Pevné události", value: "\(fixedEventCount)", icon: "calendar.badge.clock")
                    assistantRow("Místa bez GPS", value: "\(missingGPSCount)", icon: "location.slash")

                    Button {
                        prepareOffline()
                    } label: {
                        Label(preparingOffline ? "Připravuji offline…" : "Připravit cestu offline", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(preparingOffline)
                }

                if !optionalStops.isEmpty {
                    Section("Rychlejší varianta") {
                        Text(WaymintLocalization.format("%d volitelných zastávek lze zkrátit, aniž by se posunuly pevné události.", optionalStops.count))
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                        Button {
                            confirmingShortPlan = true
                        } label: {
                            Label("Zkrátit volitelná místa o 25 %", systemImage: "hare")
                        }
                    }
                }

                if let start = trip.sortedStops.first, start.coordinateIsValid {
                    Section("Bezpečný návrat") {
                        Button {
                            openInMaps(start)
                        } label: {
                            Label(WaymintLocalization.format("Navigovat zpět na %@", start.title), systemImage: "house.and.flag")
                        }
                        if !start.address.isEmpty {
                            Text(start.address).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                        }
                    }
                }

                if let assistantMessage {
                    Section {
                        Label(assistantMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(WaymintTheme.success)
                    }
                }
            }
            .navigationTitle("Asistent cesty")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .confirmationDialog("Vytvořit rychlejší variantu?", isPresented: $confirmingShortPlan, titleVisibility: .visible) {
                Button("Zkrátit volitelná místa") { shortenOptionalStops() }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Délka návštěvy volitelných míst se zkrátí o čtvrtinu a časová osa se přepočítá. Změna neodstraní žádnou zastávku.")
            }
        }
    }

    private var assistantHeadline: String {
        if let issue = issues.first { return issue.title }
        if TripStartTimingService().needsConfirmation(for: trip) { return WaymintLocalization.text("Před startem zkontroluj datum a čas") }
        return WaymintLocalization.text("Cesta je připravená")
    }

    private var assistantDetail: String {
        if let issue = issues.first { return issue.detail }
        return WaymintLocalization.text("Trasa, časy, GPS a vstupenky nevykazují zásadní problém.")
    }

    private var assistantIcon: String {
        issues.isEmpty ? "checkmark.sparkles" : "exclamationmark.triangle.fill"
    }

    private func assistantRow(_ title: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(LocalizedStringKey(value)).foregroundStyle(WaymintTheme.secondaryText)
        }
    }

    private func prepareOffline() {
        preparingOffline = true
        Task {
            let result = await TripOfflinePreparationService.prepare(trip)
            assistantMessage = WaymintLocalization.format("Offline připraveno: %d tras, %d chybějících souborů.", result.routeCount, result.missingTicketFiles)
            preparingOffline = false
        }
    }

    private func shortenOptionalStops() {
        for stop in optionalStops {
            stop.plannedVisitDurationMinutes = max(10, Int(Double(stop.plannedVisitDurationMinutes) * 0.75))
        }
        if let first = trip.sortedStops.first {
            ScheduleCalculator().recalculateTrip(trip, anchor: first.plannedArrival)
        }
        assistantMessage = WaymintLocalization.text("Volitelná místa byla zkrácena a plán je přepočítaný.")
    }

    private func openInMaps(_ stop: TripStop) {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = stop.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
