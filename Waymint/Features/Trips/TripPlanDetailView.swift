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
    @State private var showingActiveTrip = false
    @State private var showingReadiness = false
    @State private var showingStartTimingDecision = false
    @State private var isPreparingOffline = false
    @State private var offlineMessage: String?

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
                Button {
                    requestTripStart()
                } label: {
                    Label("Spustit", systemImage: "play.fill")
                }

                Menu {
                    Button { showingTripSettings = true } label: {
                        Label("Upravit cestu", systemImage: "slider.horizontal.3")
                    }
                    Button { shareTrip() } label: {
                        Label("Exportovat cestu", systemImage: "square.and.arrow.up")
                    }
                    Button { showingInstagramComposer = true } label: {
                        Label("Obrázek na Instagram", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        prepareOffline()
                    } label: {
                        Label(isPreparingOffline ? "Připravuji offline…" : "Připravit offline", systemImage: "arrow.down.circle")
                    }
                    .disabled(isPreparingOffline)
                    Button { showingReadiness = true } label: {
                        Label(TripReadinessChecker.isReady(trip) ? "Cesta je připravená" : "Cesta vyžaduje kontrolu", systemImage: TripReadinessChecker.isReady(trip) ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    }
                } label: {
                    Label("Další akce", systemImage: "ellipsis.circle")
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
        .sheet(isPresented: $showingReadiness) {
            TripReadinessView(trip: trip) {
                showingReadiness = false
                showingActiveTrip = true
            }
        }
        .navigationDestination(isPresented: $showingActiveTrip) {
            ActiveTripView(trip: trip)
        }
        .confirmationDialog("Plánovaný čas nesouhlasí", isPresented: $showingStartTimingDecision, titleVisibility: .visible) {
            Button("Přesunout plán na teď") {
                TripStartTimingService().movePlanToNow(trip)
                continueTripStart()
            }
            Button("Spustit podle původního plánu") {
                continueTripStart()
            }
            Button("Zpět do plánování") {
                showingTripSettings = true
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text(startTimingWarning)
        }
        .alert("Export se nepovedl", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .alert("Offline příprava", isPresented: Binding(get: { offlineMessage != nil }, set: { if !$0 { offlineMessage = nil } })) {
            Button("OK", role: .cancel) { offlineMessage = nil }
        } message: { Text(offlineMessage ?? "") }
    }

    private var portraitContent: some View {
        VStack(spacing: 0) {
            TripHeaderView(trip: trip)

            Picker("Režim", selection: $selectedMode) {
                ForEach(TripDetailMode.allCases) { mode in
                    Label { Text(LocalizedStringKey(mode.title)) } icon: { Image(systemName: mode.systemImage) }.tag(mode)
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

    private func requestTripStart() {
        if TripStartTimingService().needsConfirmation(for: trip) {
            showingStartTimingDecision = true
        } else {
            continueTripStart()
        }
    }

    private func continueTripStart() {
        if TripReadinessChecker.issues(for: trip).isEmpty {
            showingActiveTrip = true
        } else {
            showingReadiness = true
        }
    }

    private var startTimingWarning: String {
        let planned = TripStartTimingService().plannedStart(for: trip)
        return WaymintLocalization.format("Cesta je naplánovaná na %@ v %@, ale teď je %@ v %@. Jak ji chceš spustit?", trip.date.waymintDate, planned.waymintTime, Date().waymintDate, Date().waymintTime)
    }

    private func prepareOffline() {
        isPreparingOffline = true
        Task {
            let result = await TripOfflinePreparationService.prepare(trip)
            offlineMessage = "Uloženo tras: \(result.routeCount). Odhadovaných úseků: \(result.estimatedRouteCount). Chybějících souborů vstupenek: \(result.missingTicketFiles). Apple Mapy si spravují samotný mapový podklad systémově; Waymint uložil trasy a všechna vlastní data dostupná aplikaci."
            isPreparingOffline = false
        }
    }

}

struct TripReadinessView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: TripPlan
    let startAnyway: () -> Void

    private var issues: [TripReadinessIssue] { TripReadinessChecker.issues(for: trip) }
    private var hasBlockingIssue: Bool { issues.contains { $0.severity == .blocking } }

    var body: some View {
        NavigationStack {
            List {
                if issues.isEmpty {
                    ContentUnavailableView("Cesta je připravená", systemImage: "checkmark.shield.fill", description: Text(LocalizedStringKey("Souřadnice, přesuny, časy a soubory vstupenek jsou v pořádku.")))
                } else {
                    Section(hasBlockingIssue ? "Vyžaduje kontrolu" : "Doporučení") {
                        ForEach(issues) { issue in
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.title).font(.headline)
                                    Text(issue.detail).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                                }
                            } icon: {
                                Image(systemName: issue.systemImage)
                                    .foregroundStyle(issue.severity == .blocking ? WaymintTheme.warning : WaymintTheme.secondaryText)
                            }
                        }
                    }
                }
                Section {
                    Button {
                        startAnyway()
                    } label: {
                        Label(hasBlockingIssue ? "Přesto spustit" : "Spustit cestu", systemImage: "play.fill")
                    }
                }
            }
            .navigationTitle("Kontrola před startem")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } } }
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
    @State private var excludedStopIDs: Set<UUID> = []
    private let service = InstagramTripCardService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Styl obrázku", selection: $style) {
                    ForEach(InstagramTripCardService.Style.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)

                DisclosureGroup("Místa v trase") {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(trip.sortedStops.filter(\.coordinateIsValid)) { stop in
                                Toggle(isOn: inclusionBinding(for: stop)) {
                                    Label(stop.title, systemImage: stop.stopType.systemImage)
                                        .lineLimit(1)
                                }
                                .disabled(!excludedStopIDs.contains(stop.id) && includedStopCount <= 2)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }

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
            .task(id: generationKey) { await generatePreview() }
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
            let url = try await service.create(for: trip, style: style, excludedStopIDs: excludedStopIDs)
            guard !Task.isCancelled else { return }
            imageURL = url
            previewImage = UIImage(contentsOfFile: url.path)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private var includedStopCount: Int {
        trip.sortedStops.filter { $0.coordinateIsValid && !excludedStopIDs.contains($0.id) }.count
    }

    private var generationKey: String {
        style.rawValue + excludedStopIDs.map(\.uuidString).sorted().joined()
    }

    private func inclusionBinding(for stop: TripStop) -> Binding<Bool> {
        Binding(
            get: { !excludedStopIDs.contains(stop.id) },
            set: { included in
                if included { excludedStopIDs.remove(stop.id) }
                else if includedStopCount > 2 { excludedStopIDs.insert(stop.id) }
            }
        )
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
    @State private var isDescriptionExpanded = false

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
                Label(WaymintLocalization.format("%d zastávek", trip.stopCount), systemImage: "mappin.and.ellipse")
                Label((trip.hasFixedStartTime ? trip.approximateDurationMinutes : trip.expectedContentDurationMinutes).minutesLabel, systemImage: "clock")
                if trip.totalTicketCount > 0 {
                    Label(WaymintLocalization.format("%d vstupenek", trip.totalTicketCount), systemImage: "ticket.fill")
                }
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
