import SwiftData
import SwiftUI
import MapKit
import Combine

struct StopFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
    @State private var bankPlaceHighlights = ""
    @State private var selectedBankPlace: PlaceBankItem?
    @State private var showingBankPlacePicker = false
    @State private var saveToPlaceBank = false
    @State private var updateSourceBankPlace = false
    @State private var isTimeAnchor = false
    @State private var routeEstimationID = UUID()
    @AppStorage("waymintPlaceBankEnabled") private var placeBankEnabled = false

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
                if let selectedBankPlace {
                    Section("Vybrané místo") {
                        Label(selectedBankPlace.title, systemImage: selectedBankPlace.stopType.systemImage)
                            .font(.headline)
                        if !selectedBankPlace.mainReason.isEmpty {
                            Text(selectedBankPlace.mainReason)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                        Label(WaymintLocalization.format("Doporučený čas: %@", plannedVisitDurationMinutes.minutesLabel), systemImage: "clock")
                        Button("Vybrat jiné místo") {
                            self.selectedBankPlace = nil
                        }
                    }

                    if !isFirstStop, previousStop != nil {
                        Section("Jak se tam dostanu") {
                            Picker("Doprava", selection: $transportMode) {
                                ForEach(TransportMode.allCases) { mode in
                                    Label { Text(LocalizedStringKey(mode.title)) } icon: { Image(systemName: mode.systemImage) }.tag(mode)
                                }
                            }
                            .onChange(of: transportMode) { _, _ in estimateRouteIfPossible() }

                            Stepper(WaymintLocalization.format("Doba přesunu: %@", travelDurationMinutes.minutesLabel), value: $travelDurationMinutes, in: 1...240, step: 5)
                                .onChange(of: travelDurationMinutes) { _, _ in updateArrivalFromTravel() }
                            Stepper("Rezerva: \(travelBufferMinutes.minutesLabel)", value: $travelBufferMinutes, in: 0...120, step: 5)
                                .onChange(of: travelBufferMinutes) { _, _ in updateArrivalFromTravel() }

                            Button(action: estimateRouteIfPossible) {
                                Label(isEstimatingRoute ? "Počítám trasu…" : "Spočítat podle Apple Map", systemImage: "map")
                            }
                            .disabled(isEstimatingRoute || selectedCoordinate == nil || previousStopCoordinate == nil)

                            if let routeMessage {
                                Text(routeMessage).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                            }
                        }
                    }
                } else {
                if placeBankEnabled, stop == nil, let city = trip.city, !city.sortedBankPlaces.isEmpty {
                    Section("Banka míst") {
                        Button {
                            showingBankPlacePicker = true
                        } label: {
                            Label("Vybrat uložené místo", systemImage: "square.grid.2x2")
                        }
                        Text("Waymint doplní údaje místa a doporučenou délku. Přesun z předchozí zastávky nastavíš níže.")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }

                Section(isFirstStop ? "Start cesty" : "Základ") {
                    TextField(isFirstStop ? "Odkud cesta začíná" : "Název zastávky", text: $title)
                    Picker("Typ", selection: $stopType) {
                        ForEach(StopType.allCases) { type in
                            Label { Text(LocalizedStringKey(type.title)) } icon: { Image(systemName: type.systemImage) }.tag(type)
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
                            Text(LocalizedStringKey(status.title)).tag(status)
                        }
                    }
                    Toggle("Povinná zastávka", isOn: $isRequired)

                    if isFirstStop {
                        Label("První bod se v plánu bere jako start. Další zastávky už ukazují dojezd z tohohle místa.", systemImage: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }

                Section("Čas") {
                    DatePicker(isFirstStop ? "Začátek" : "Příchod", selection: $plannedArrival, displayedComponents: [.date, .hourAndMinute])
                    if stopType == .transfer {
                        Label("Přesun nemá délku návštěvy. Odchod se bere podle příchodu.", systemImage: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    } else {
                        Stepper(
                            WaymintLocalization.format(
                                isFirstStop ? "Čas na startu: %@" : "Délka návštěvy: %@",
                                plannedVisitDurationMinutes.minutesLabel
                            ),
                            value: $plannedVisitDurationMinutes,
                            in: 0...480,
                            step: 5
                        )
                    }
                    Text(WaymintLocalization.format("Odchod: %@", calculator.plannedDeparture(arrival: plannedArrival, visitDurationMinutes: plannedVisitDurationMinutes).waymintTime))
                        .foregroundStyle(WaymintTheme.secondaryText)
                    if !isFirstStop {
                        Toggle("Pevný čas / rezervace", isOn: $isTimeAnchor)
                        if isTimeAnchor {
                            Text("Tento čas zůstane při automatickém přepočtu zachovaný, například pro trajekt, vlak nebo rezervovaný vstup.")
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                    }
                }

                Section("Místo") {
                    HStack {
                        TextField("Najít místo v Apple Mapách", text: $placeSearch.query)
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
                            Marker(title.isEmpty ? "Vybrané místo" : title, coordinate: selectedCoordinate)
                        }
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                    }

                    Button {
                        showingMapPointPicker = true
                    } label: {
                        Label(selectedCoordinate == nil ? "Vybrat bod na mapě" : "Upravit bod na mapě", systemImage: "mappin.and.ellipse")
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

                if !isFirstStop, previousStop != nil {
                    Section("Přesun z předchozí zastávky") {
                        Picker("Doprava", selection: $transportMode) {
                            ForEach(TransportMode.allCases) { mode in
                                Label { Text(LocalizedStringKey(mode.title)) } icon: { Image(systemName: mode.systemImage) }.tag(mode)
                            }
                        }
                        .onChange(of: transportMode) { _, _ in
                            estimateRouteIfPossible()
                        }

                        if stopType == .transfer {
                            Text("Tahle zastávka je označená jako přesun, proto počítám návštěvu jako 0 minut a hlavní čas beru z trasy.")
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }

                        Stepper(WaymintLocalization.format("Doba přesunu: %@", travelDurationMinutes.minutesLabel), value: $travelDurationMinutes, in: 1...240, step: 5)
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
                            Label(isEstimatingRoute ? "Počítám trasu…" : "Spočítat podle Apple Map", systemImage: "map")
                        }
                        .disabled(isEstimatingRoute || selectedCoordinate == nil || previousStopCoordinate == nil)

                        if let routeMessage {
                            Text(routeMessage)
                                .font(.caption)
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                    }
                }

                Section("Proč sem jdu") {
                    TextField("Hlavní tahák", text: $mainReason, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Poznámka", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                if placeBankEnabled, stop == nil, selectedBankPlace == nil, trip.city != nil {
                    Section("Banka míst") {
                        Toggle("Uložit také do banky míst", isOn: $saveToPlaceBank)
                    }
                }
                if placeBankEnabled, stop?.sourceBankPlaceID != nil {
                    Section("Banka míst") {
                        Toggle("Promítnout změny také do banky", isOn: $updateSourceBankPlace)
                    }
                }

                if stop == nil {
                    Section("První položka checklistu") {
                        TextField("Co chci vidět", text: $firstChecklistItem)
                    }
                }
                }
            }
            .navigationTitle(Text(LocalizedStringKey(stop == nil ? "Nová zastávka" : "Upravit zastávku")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingMapPointPicker) {
                MapPointPickerView(
                    initialCoordinate: selectedCoordinate,
                    title: title.isEmpty ? "Vybrat místo" : title
                ) { coordinate in
                    applyManualCoordinate(coordinate)
                }
            }
            .sheet(isPresented: $showingBankPlacePicker) {
                if let city = trip.city {
                    BankPlacePickerView(places: city.sortedBankPlaces) { place in
                        applyBankPlace(place)
                    }
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
        guard let previousStop,
              let latitude = previousStop.latitude,
              let longitude = previousStop.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var editedStopIndex: Int? {
        guard let stop else { return nil }
        return trip.sortedStops.firstIndex { $0.id == stop.id }
    }

    private var previousStop: TripStop? {
        if let editedStopIndex {
            guard editedStopIndex > 0 else { return nil }
            return trip.sortedStops[editedStopIndex - 1]
        }
        return trip.sortedStops.last
    }

    private var inboundSegment: TravelSegment? {
        guard let stop else { return nil }
        return trip.sortedTravelSegments.first { $0.toStopID == stop.id }
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
        isTimeAnchor = stop.isTimeAnchor
        if let inboundSegment {
            transportMode = inboundSegment.transportMode
            travelDurationMinutes = max(1, inboundSegment.plannedDurationMinutes)
            travelBufferMinutes = inboundSegment.bufferMinutes
        }
        updateSourceBankPlace = stop.sourceBankPlaceID != nil
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
            stop.isTimeAnchor = isTimeAnchor
            stop.updatedAt = .now

            if updateSourceBankPlace,
               let sourceID = stop.sourceBankPlaceID,
               let bankPlace = trip.city?.sortedBankPlaces.first(where: { $0.id == sourceID }) {
                bankPlace.title = stop.title
                bankPlace.stopType = stop.stopType
                bankPlace.mainReason = stop.mainReason
                bankPlace.note = stop.note
                bankPlace.recommendedVisitDurationMinutes = stop.plannedVisitDurationMinutes
                bankPlace.address = stop.address
                bankPlace.latitude = stop.latitude
                bankPlace.longitude = stop.longitude
                bankPlace.updatedAt = .now
            }

            if let previousStop {
                let segment = inboundSegment ?? TravelSegment(
                    fromStopID: previousStop.id,
                    toStopID: stop.id,
                    sortIndex: max(0, stop.sortIndex - 1)
                )
                segment.transportMode = transportMode
                segment.plannedDurationMinutes = max(1, travelDurationMinutes)
                segment.bufferMinutes = travelBufferMinutes
                segment.plannedDeparture = previousStop.plannedDeparture
                segment.fromStopID = previousStop.id
                segment.toStopID = stop.id
                if inboundSegment == nil {
                    trip.addTravelSegment(segment)
                }
            }

            if let index = trip.sortedStops.firstIndex(where: { $0.id == stop.id }) {
                calculator.recalculateFromArrival(
                    plannedArrival,
                    at: index,
                    stops: trip.sortedStops,
                    segments: trip.sortedTravelSegments
                )
            }
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
                sortIndex: nextSortIndex,
                sourceBankPlaceID: selectedBankPlace?.id,
                isTimeAnchor: isTimeAnchor
            )

            let checklistTitle = firstChecklistItem.trimmingCharacters(in: .whitespacesAndNewlines)
            if !checklistTitle.isEmpty {
                newStop.addChecklistItem(StopChecklistItem(title: checklistTitle))
            }
            for (index, highlight) in bankPlaceHighlights
                .components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .filter({ !$0.isEmpty })
                .enumerated() {
                newStop.addChecklistItem(StopChecklistItem(title: highlight, sortIndex: index + (checklistTitle.isEmpty ? 0 : 1)))
            }

            trip.addStop(newStop)

            if saveToPlaceBank, let city = trip.city,
               !city.sortedBankPlaces.contains(where: {
                   PlaceBankDeduplicator.matches(
                       title: newStop.title,
                       address: newStop.address,
                       latitude: newStop.latitude,
                       longitude: newStop.longitude,
                       place: $0
                   )
               }) {
                let bankPlace = PlaceBankItem(
                    title: newStop.title,
                    stopType: newStop.stopType,
                    highlights: firstChecklistItem,
                    mainReason: newStop.mainReason,
                    note: newStop.note,
                    recommendedVisitDurationMinutes: newStop.plannedVisitDurationMinutes,
                    address: newStop.address,
                    latitude: newStop.latitude,
                    longitude: newStop.longitude
                )
                bankPlace.city = city
                city.addBankPlace(bankPlace)
                modelContext.insert(bankPlace)
            }

            if let previousStop = trip.sortedStops.dropLast().last {
                trip.addTravelSegment(
                    TravelSegment(
                        transportMode: transportMode,
                        plannedDurationMinutes: max(1, travelDurationMinutes),
                        plannedDeparture: previousStop.plannedDeparture,
                        bufferMinutes: travelBufferMinutes,
                        fromStopID: previousStop.id,
                        toStopID: newStop.id,
                        sortIndex: max(0, nextSortIndex - 1)
                    )
                )
            }
        }

        trip.updatedAt = .now

        dismiss()
    }

    private func applyBankPlace(_ place: PlaceBankItem) {
        selectedBankPlace = place
        title = place.title
        stopType = place.stopType
        plannedVisitDurationMinutes = place.recommendedVisitDurationMinutes
        address = place.address
        latitudeText = place.latitude.map { String($0) } ?? ""
        longitudeText = place.longitude.map { String($0) } ?? ""
        mainReason = place.mainReason
        note = place.note
        bankPlaceHighlights = place.highlights
        placeSearch.query = place.title
        updateMapPosition()
        estimateRouteIfPossible()
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
            address = WaymintLocalization.text("Ručně vybraný bod")
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
        guard let previousStopCoordinate,
              let selectedCoordinate else { return }

        let requestID = UUID()
        routeEstimationID = requestID
        isEstimatingRoute = true
        routeMessage = nil
        Task {
            do {
                let minutes = try await routePlanner.estimatedDurationMinutes(
                    from: previousStopCoordinate,
                    to: selectedCoordinate,
                    transportMode: transportMode
                )
                guard routeEstimationID == requestID else { return }
                travelDurationMinutes = minutes
                updateArrivalFromTravel()
                routeMessage = WaymintLocalization.format("Apple Mapy odhadují přesun na %@.", minutes.minutesLabel)
            } catch {
                guard routeEstimationID == requestID else { return }
                routeMessage = WaymintLocalization.text("Trasu se teď přes Apple Mapy nepodařilo spočítat. Ponechávám ruční čas.")
            }
            if routeEstimationID == requestID {
                isEstimatingRoute = false
            }
        }
    }

    private func updateArrivalFromTravel() {
        guard let previousStop else { return }
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

private struct BankPlacePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let places: [PlaceBankItem]
    let onSelect: (PlaceBankItem) -> Void
    @State private var searchText = ""

    private var filteredPlaces: [PlaceBankItem] {
        guard !searchText.isEmpty else { return places }
        return places.filter {
            $0.title.localizedStandardContains(searchText) ||
            $0.mainReason.localizedStandardContains(searchText) ||
            $0.highlights.localizedStandardContains(searchText) ||
            $0.address.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredPlaces) { place in
                Button {
                    onSelect(place)
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: place.stopType.systemImage)
                            .font(.title2)
                            .foregroundStyle(WaymintTheme.primaryGreen)
                            .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(place.title)
                                .font(.headline)
                                .foregroundStyle(WaymintTheme.primaryText)

                            if !place.mainReason.isEmpty {
                                Text(place.mainReason)
                                    .font(.subheadline)
                                    .foregroundStyle(WaymintTheme.secondaryText)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 12) {
                                Label(place.recommendedVisitDurationMinutes.minutesLabel, systemImage: "clock")
                                if !place.address.isEmpty {
                                    Label(place.address, systemImage: "mappin")
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)

                            if !place.highlights.isEmpty {
                                Label(place.highlights.replacingOccurrences(of: "\n", with: " · "), systemImage: "checklist")
                                    .font(.caption)
                                    .foregroundStyle(WaymintTheme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Hledat v bance míst")
            .navigationTitle("Vybrat místo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
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
                    Text("Klepni do mapy a nastav přesný bod.")
                        .font(.headline)
                    Text("\(selectedCoordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(selectedCoordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.regularMaterial)
            }
            .navigationTitle("Bod na mapě")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Použít") {
                        onSelect(selectedCoordinate)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PlaceSearchResult: Identifiable {
    let id = UUID()
    let item: MKMapItem

    var title: String {
        item.name ?? WaymintLocalization.text("Místo")
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
final class PlaceSearchService: NSObject, ObservableObject {
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
            errorMessage = mapItems.isEmpty ? WaymintLocalization.text("Nic jsem nenašel. Zkus přesnější název nebo město.") : nil
        } catch {
            mapItems = []
            errorMessage = WaymintLocalization.text("Vyhledávání se nepodařilo. Apple Mapy potřebují připojení k internetu.")
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
            errorMessage = WaymintLocalization.text("Místo se nepodařilo načíst. Zkus upravit hledaný text.")
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
            errorMessage = WaymintLocalization.text("Vyhledávání v Apple Mapách teď není dostupné.")
            results = []
        }
    }
}

#Preview {
    StopFormView(trip: TripPlan(title: "Centrum"), stop: nil, nextSortIndex: 0)
        .modelContainer(PreviewData.container())
}
