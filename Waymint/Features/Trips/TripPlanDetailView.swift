import SwiftData
import SwiftUI

struct TripPlanDetailView: View {
    @Bindable var trip: TripPlan

    @State private var selectedMode = TripDetailMode.timeline
    @State private var showingNewStop = false
    @State private var showingNewTicket = false
    @State private var showingTripSettings = false
    @State private var exportedWayFile: ExportedWayFile?
    @State private var exportErrorMessage = ""
    @State private var showingExportError = false

    private let exportService = WaymintExportService()

    var body: some View {
        VStack(spacing: 0) {
            TripHeaderView(trip: trip)

            Picker("Rezim", selection: $selectedMode) {
                ForEach(TripDetailMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 10)

            Group {
                switch selectedMode {
                case .timeline:
                    TimelineView(trip: trip)
                case .map:
                    TripMapView(trip: trip)
                case .tickets:
                    TicketsOverviewView(trip: trip)
                }
            }
        }
        .background(WaymintTheme.elevatedSurface)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    ActiveTripView(trip: trip)
                } label: {
                    Label("Spustit", systemImage: "play.fill")
                }

                Button {
                    showingTripSettings = true
                } label: {
                    Label("Upravit cestu", systemImage: "slider.horizontal.3")
                }

                Button {
                    shareTrip()
                } label: {
                    Label("Sdílet cestu", systemImage: "square.and.arrow.up")
                }

                Button {
                    if selectedMode == .tickets {
                        showingNewTicket = true
                    } else {
                        showingNewStop = true
                    }
                } label: {
                    Label(selectedMode == .tickets ? "Přidat vstupenku" : "Přidat zastávku", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewStop) {
            StopFormView(trip: trip, stop: nil, nextSortIndex: trip.stopCount)
        }
        .sheet(isPresented: $showingNewTicket) {
            TicketFormView(trip: trip, stop: nil)
        }
        .sheet(isPresented: $showingTripSettings) {
            if let city = trip.city {
                TripPlanFormView(city: city, trip: trip, nextSortIndex: city.tripPlanCount)
            }
        }
        .sheet(item: $exportedWayFile) { file in
            ShareSheet(activityItems: [
                WaymintFileActivityItem(url: file.url, title: "Waymint \(trip.title)")
            ])
        }
        .alert("Export se nepovedl", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func shareTrip() {
        do {
            exportedWayFile = ExportedWayFile(url: try exportService.exportTrip(trip))
        } catch {
            exportErrorMessage = error.localizedDescription
            showingExportError = true
        }
    }
}

private enum TripDetailMode: String, CaseIterable, Identifiable {
    case timeline
    case map
    case tickets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeline: "Časová osa"
        case .map: "Mapa"
        case .tickets: "Vstupenky"
        }
    }

    var systemImage: String {
        switch self {
        case .timeline: "list.bullet.rectangle"
        case .map: "map"
        case .tickets: "ticket"
        }
    }
}

private struct TripHeaderView: View {
    let trip: TripPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.date.waymintDate)
                        .font(.subheadline)
                        .foregroundStyle(WaymintTheme.secondaryText)
                    Text(trip.scheduleLabel)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(WaymintTheme.darkGreen)
                }
                Spacer()
                StatusPill(trip.status.title, systemImage: "flag")
            }

            HStack(spacing: 12) {
                Label("\(trip.stopCount) zastávek", systemImage: "mappin.and.ellipse")
                Label(trip.hasFixedStartTime ? trip.approximateDurationMinutes.minutesLabel : trip.scheduleLabel, systemImage: "clock")
                Label("\(trip.ticketCount) vstupenek", systemImage: "ticket.fill")
            }
            .font(.caption)
            .foregroundStyle(WaymintTheme.secondaryText)

            if !trip.landingTitle.isEmpty || !trip.landingSubtitle.isEmpty || trip.photoAlbumTitle != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if !trip.landingTitle.isEmpty {
                        Text(trip.landingTitle)
                            .font(.headline)
                    }
                    if !trip.landingSubtitle.isEmpty {
                        Text(trip.landingSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    if let photoAlbumTitle = trip.photoAlbumTitle {
                        Label(photoAlbumTitle, systemImage: "photo.on.rectangle.angled")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WaymintTheme.primaryGreen)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WaymintTheme.lightGreen.opacity(0.38), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
            }
        }
        .padding()
        .background(WaymintTheme.elevatedSurface)
    }
}

#Preview {
    NavigationStack {
        TripPlanDetailView(trip: TripPlan(title: "Centrum Helsinek"))
    }
    .modelContainer(PreviewData.container())
}
