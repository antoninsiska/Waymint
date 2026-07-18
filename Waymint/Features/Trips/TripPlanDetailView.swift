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
    @State private var showingInstagramComposer = false

    private let exportService = WaymintExportService()

    var body: some View {
        GeometryReader { proxy in
            if UIDevice.current.userInterfaceIdiom == .phone,
               proxy.size.width > proxy.size.height {
                PhoneLandscapeTripPlannerView(trip: trip)
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                portraitContent
                    .toolbar(.visible, for: .navigationBar)
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
                    showingInstagramComposer = true
                } label: {
                    Label("Obrázek na Instagram", systemImage: "photo.on.rectangle.angled")
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
        .sheet(isPresented: $showingInstagramComposer) {
            InstagramTripCardComposerView(trip: trip)
        }
        .alert("Export se nepovedl", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private var portraitContent: some View {
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

private struct InstagramTripCardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: TripPlan
    @State private var style = InstagramTripCardService.Style.dark
    @State private var imageURL: URL?
    @State private var previewImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    private let service = InstagramTripCardService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Vzhled", selection: $style) {
                    ForEach(InstagramTripCardService.Style.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(WaymintTheme.elevatedSurface)
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(8)
                    } else if isLoading {
                        ProgressView("Vytvářím mapu…")
                    } else if let errorMessage {
                        ContentUnavailableView("Náhled se nepovedl", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    showingShareSheet = true
                } label: {
                    Label("Sdílet obrázek", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(imageURL == nil || isLoading)
            }
            .padding()
            .navigationTitle("Instagram obrázek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } } }
            .task(id: style) { await generatePreview() }
            .sheet(isPresented: $showingShareSheet) {
                if let imageURL { ShareSheet(activityItems: [imageURL]) }
            }
        }
    }

    private func generatePreview() async {
        isLoading = true
        errorMessage = nil
        imageURL = nil
        previewImage = nil
        do {
            let url = try await service.create(for: trip, style: style)
            imageURL = url
            previewImage = UIImage(contentsOfFile: url.path)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
    @State private var isDescriptionExpanded = true

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

            if hasDescription {
                VStack(alignment: .leading, spacing: isDescriptionExpanded ? 8 : 0) {
                    Button {
                        withAnimation(.snappy) {
                            isDescriptionExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(isDescriptionExpanded ? "Informace o cestě" : "Zobrazit název a popis")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: isDescriptionExpanded ? "chevron.up" : "chevron.down")
                        }
                        .foregroundStyle(WaymintTheme.primaryGreen)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isDescriptionExpanded {
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
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WaymintTheme.lightGreen.opacity(0.38), in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
            }
        }
        .padding()
        .background(WaymintTheme.elevatedSurface)
    }

    private var hasDescription: Bool {
        !trip.landingTitle.isEmpty || !trip.landingSubtitle.isEmpty || trip.photoAlbumTitle != nil
    }
}

#Preview {
    NavigationStack {
        TripPlanDetailView(trip: TripPlan(title: "Centrum Helsinek"))
    }
    .modelContainer(PreviewData.container())
}
