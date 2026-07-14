import SwiftData
import SwiftUI
import MapKit
import Combine

struct StopFormView: View {
    @Environment(\.dismiss) private var dismiss

    let trip: TripPlan
    let stop: TripStop?
    let nextSortIndex: Int

    @State private var title = ""
    @State private var stopType = StopType.custom
    @State private var status = StopStatus.planned
    @State private var plannedArrival = Date()
    @State private var plannedVisitDurationMinutes = 45
    @State private var address = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @StateObject private var placeSearch = PlaceSearchService()
    @State private var mapPickerPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    )
    @State private var showingMapPointPicker = false
    @State private var routeMessage: String?
    @State private var isEstimatingRoute = false
    @State private var note = ""
    @State private var mainReason = ""
    @State private var isRequired = true
    @State private var firstChecklistItem = ""
    @State private var transportMode = TransportMode.walking
    @State private var travelDurationMinutes = 10
    @State private var travelBufferMinutes = 0

    private let calculator = ScheduleCalculator()
    private let routePlanner = RoutePlanningService()

    private var isFirstStop: Bool {
        if let stop {
            return trip.sortedStops.first?.id == stop.id
        }
        return trip.sortedStops.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isFirstStop ? "Start cesty" : "Základ") {
                    TextField(isFirstStop ? "Odkud cesta začíná" : "Název zastávky", text: $title)
                    Picker("Typ", selection: $stopType) {
                        ForEach(StopType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .onChange(of: stopType) { _, newValue in
                        if newValue == .transfer {
                            plannedVisitDurationMinutes = 0
                        } else if plannedVisitDurationMinutes == 0 {
                            plannedVisitDurationMinutes = 30
                        }
                    }
                    Picker("Stav", selection: $status) {
                        ForEach(StopStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Toggle("Povinna zastavka", isOn: $isRequired)

                    if isFirstStop {
                        Label("První bod se v plánu bere jako start. Další zastávky už ukazují dojezd z tohohle místa.", systemImage: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }

                Section("Cas") {
                    DatePicker(isFirstStop ? "Začátek" : "Příchod", selection: $plannedArrival, displayedComponents: [.date, .hourAndMinute])
                    if stopType == .transfer {
                        Label("Přesun nemá délku návštěvy. Odchod se bere podle příchodu.", systemImage: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    } else {
                        Stepper(isFirstStop ? "Čas na startu: \(plannedVisitDurationMinutes.minutesLabel)" : "Délka návštěvy: \(plannedVisitDurationMinutes.minutesLabel)", value: $plannedVisitDurationMinutes, in: 0...480, step: 5)
                    }
                    Text("Odchod: \(calculator.plannedDeparture(arrival: plannedArrival, visitDurationMinutes: plannedVisitDurationMinutes).waymintTime)")
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("Misto") {
                    HStack {
                        TextField("Najit misto v Apple Mapach", text: $placeSearch.query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit {
                                searchPlaces()
                            }

                        Button {
                            searchPlaces()
                        } label: {
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        .disabled(placeSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if placeSearch.isSearching {
                        ProgressView()
                    }

                    if !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }

                    if let selectedCoordinate {
                        Map(position: $mapPickerPosition) {
                            Marker(title.isEmpty ? "Vybrane misto" : title, coordinate: selectedCoordinate)
                        }
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                    }

                    Button {
                        showingMapPointPicker = true
                    } label: {
                        Label(selectedCoordinate == nil ? "Vybrat bod na mape" : "Upravit bod na mape", systemImage: "mappin.and.ellipse")
                    }

                    if let errorMessage = placeSearch.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.warning)
                    }

                    ForEach(placeSearch.results.prefix(5), id: \.self) { result in
                        Button {
                            selectPlace(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .foregroundStyle(WaymintTheme.primaryText)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }

                    ForEach(placeSearch.mapItems) { result in
                        Button {
                            selectMapItem(result.item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.title)
                                    .foregroundStyle(WaymintTheme.primaryText)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }
                }

                if stop == nil, trip.sortedStops.last != nil {
                    Section("Presun z predchozi zastavky") {
                        Picker("Doprava", selection: $transportMode) {
                            ForEach(TransportMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        .onChange(of: transportMode) { _, _ in
                            estimateRouteIfPossible()
                        }

                        if stopType == .transfer {
                            Text("Tahle zastavka je oznacena jako presun, proto pocitam navstevu jako 0 minut a hlavni cas beru z trasy.")
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }

                        Stepper("Doba presunu: \(travelDurationMinutes.minutesLabel)", value: $travelDurationMinutes, in: 0...240, step: 5)
                            .onChange(of: travelDurationMinutes) { _, _ in
                                updateArrivalFromTravel()
                            }
                        Stepper("Rezerva: \(travelBufferMinutes.minutesLabel)", value: $travelBufferMinutes, in: 0...120, step: 5)
                            .onChange(of: travelBufferMinutes) { _, _ in
                                updateArrivalFromTravel()
                            }

                        Button {
                            estimateRouteIfPossible()
                        } label: {
                            Label(isEstimatingRoute ? "Pocitam trasu..." : "Spocitat podle Apple Map", systemImage: "map")
                        }
                        .disabled(isEstimatingRoute || selectedCoordinate == nil || previousStopCoordinate == nil)

                        if let routeMessage {
                            Text(routeMessage)
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                    }
                }

                Section("Proc sem jdu") {
                    TextField("Hlavni tahak", text: $mainReason, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Poznamka", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if stop == nil {
                    Section("Prvni polozka checklistu") {
                        TextField("Co chci videt", text: $firstChecklistItem)
                    }
                }
            }
            .navigationTitle(stop == nil ? "Nova zastavka" : "Upravit zastavku")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ulozit", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingMapPointPicker) {
                MapPointPickerView(
                    initialCoordinate: selectedCoordinate,
                    title: title.isEmpty ? "Vybrat misto" : title
                ) { coordinate in
                    applyManualCoordinate(coordinate)
                }
            }
        }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var previousStopCoordinate: CLLocationCoordinate2D? {
        guard let previousStop = trip.sortedStops.last,
              let latitude = previousStop.latitude,
              let longitude = previousStop.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func load() {
        guard let stop else {
            plannedArrival = trip.sortedStops.last?.plannedDeparture ?? (trip.hasFixedStartTime ? trip.startTime : .now)
            updateArrivalFromTravel()
            if stopType == .transfer {
                plannedVisitDurationMinutes = 0
            }
            return
        }

        title = stop.title
        stopType = stop.stopType
        status = stop.status
        plannedArrival = stop.plannedArrival
        plannedVisitDurationMinutes = stop.plannedVisitDurationMinutes
        address = stop.address
        latitudeText = stop.latitude.map { String($0) } ?? ""
        longitudeText = stop.longitude.map { String($0) } ?? ""
        placeSearch.query = stop.title
        note = stop.note
        mainReason = stop.mainReason
        isRequired = stop.isRequired
        updateMapPosition()
    }

    private func save() {
        let plannedDeparture = calculator.plannedDeparture(
            arrival: plannedArrival,
            visitDurationMinutes: effectiveVisitDurationMinutes
        )
        let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: "."))

        if let stop {
            stop.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            stop.stopType = stopType
            stop.status = status
            stop.plannedArrival = plannedArrival
            stop.plannedDeparture = plannedDeparture
            stop.plannedVisitDurationMinutes = effectiveVisitDurationMinutes
            stop.address = address
            stop.latitude = latitude
            stop.longitude = longitude
            stop.note = note
            stop.mainReason = mainReason
            stop.isRequired = isRequired
            stop.updatedAt = .now
        } else {
            let newStop = TripStop(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                stopType: stopType,
                status: status,
                plannedArrival: plannedArrival,
                plannedDeparture: plannedDeparture,
                plannedVisitDurationMinutes: effectiveVisitDurationMinutes,
                address: address,
                latitude: latitude,
                longitude: longitude,
                note: note,
                mainReason: mainReason,
                isRequired: isRequired,
                sortIndex: nextSortIndex
            )

            let checklistTitle = firstChecklistItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if !checklistTitle.isEmpty {
                newStop.addChecklistItem(StopChecklistItem(title: checklistTitle))
            }

            trip.addStop(newStop)

            if let previousStop = trip.sortedStops.dropLast().last {
                trip.addTravelSegment(
                    TravelSegment(
                        transportMode: transportMode,
                        plannedDurationMinutes: travelDurationMinutes,
                        plannedDeparture: previousStop.plannedDeparture,
                        bufferMinutes: travelBufferMinutes,
                        fromStopID: previousStop.id,
                        toStopID: newStop.id,
                        sortIndex: max(0, nextSortIndex - 1)
                    )
                )
            }
        }

        dismiss()
    }

    private func selectPlace(_ result: MKLocalSearchCompletion) {
        Task {
            guard let item = await placeSearch.resolve(result) else { return }
            selectMapItem(item)
        }
    }

    private func searchPlaces() {
        Task {
            await placeSearch.search()
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        title = item.name ?? placeSearch.query
        address = formattedAddress(for: item)
        latitudeText = String(item.placemark.coordinate.latitude)
        longitudeText = String(item.placemark.coordinate.longitude)
        updateMapPosition()
        estimateRouteIfPossible()
        placeSearch.clear()
    }

    private var effectiveVisitDurationMinutes: Int {
        stopType == .transfer ? 0 : plannedVisitDurationMinutes
    }

    private func applyManualCoordinate(_ coordinate: CLLocationCoordinate2D) {
        latitudeText = String(coordinate.latitude)
        longitudeText = String(coordinate.longitude)
        if address.isEmpty {
            address = "Rucne vybrany bod"
        }
        updateMapPosition()
        estimateRouteIfPossible()
    }

    private func updateMapPosition() {
        guard let selectedCoordinate else { return }
        mapPickerPosition = .region(
            MKCoordinateRegion(
                center: selectedCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    private func estimateRouteIfPossible() {
        guard stop == nil,
              let previousStopCoordinate,
              let selectedCoordinate else { return }

        isEstimatingRoute = true
        routeMessage = nil
        Task {
            do {
                let minutes = try await routePlanner.estimatedDurationMinutes(
                    from: previousStopCoordinate,
                    to: selectedCoordinate,
                    transportMode: transportMode
                )
                travelDurationMinutes = minutes
                updateArrivalFromTravel()
                routeMessage = "Apple Mapy odhaduji presun na \(minutes.minutesLabel)."
            } catch {
                routeMessage = "Trasou podle Apple Map se ted nepodarilo spocitat. Nechavam rucni cas."
            }
            isEstimatingRoute = false
        }
    }

    private func updateArrivalFromTravel() {
        guard stop == nil, let previousStop = trip.sortedStops.last else { return }
        plannedArrival = previousStop.plannedDeparture.addingTimeInterval(TimeInterval((travelDurationMinutes + travelBufferMinutes) * 60))
    }

    private func formattedAddress(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")

        return [
            street.isEmpty ? nil : street,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct MapPointPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let initialCoordinate: CLLocationCoordinate2D?
    let title: String
    let onSelect: (CLLocationCoordinate2D) -> Void

    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var position: MapCameraPosition

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        title: String,
        onSelect: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        let coordinate = initialCoordinate ?? CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378)
        self.initialCoordinate = initialCoordinate
        self.title = title
        self.onSelect = onSelect
        _selectedCoordinate = State(initialValue: coordinate)
        _position = State(initialValue: .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        ))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    Marker(title, coordinate: selectedCoordinate)
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) {
                        selectedCoordinate = coordinate
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Klepni do mapy a nastav presny bod.")
                        .font(.headline)
                    Text("\(selectedCoordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(selectedCoordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.regularMaterial)
            }
            .navigationTitle("Bod na mape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrusit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pouzit") {
                        onSelect(selectedCoordinate)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let item: MKMapItem

    var title: String {
        item.name ?? "Misto"
    }

    var subtitle: String {
        [
            item.placemark.thoroughfare,
            item.placemark.locality,
            item.placemark.country
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

@MainActor
private final class PlaceSearchService: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            completer.queryFragment = query
        }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var mapItems: [PlaceSearchResult] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func clear() {
        query = ""
        results = []
        mapItems = []
        errorMessage = nil
    }

    func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmedQuery
            request.resultTypes = [.address, .pointOfInterest]
            let response = try await MKLocalSearch(request: request).start()
            mapItems = response.mapItems.prefix(8).map(PlaceSearchResult.init(item:))
            results = []
            errorMessage = mapItems.isEmpty ? "Nic jsem nenasel. Zkus presnejsi nazev nebo mesto." : nil
        } catch {
            mapItems = []
            errorMessage = "Vyhledavani se nepodarilo. Apple Mapy potrebuji pripojeni k internetu."
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        isSearching = true
        defer { isSearching = false }

        do {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.first
        } catch {
            errorMessage = "Misto se nepodarilo nacist. Zkus upravit hledany text."
            return nil
        }
    }
}

extension PlaceSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            errorMessage = "Vyhledavani v Apple Mapach ted neni dostupne."
            results = []
        }
    }
}

#Preview {
    StopFormView(trip: TripPlan(title: "Centrum"), stop: nil, nextSortIndex: 0)
        .modelContainer(PreviewData.container())
}
