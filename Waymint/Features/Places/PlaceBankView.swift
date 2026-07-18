import MapKit
import SwiftData
import SwiftUI

struct PlaceBankView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CityPlan.sortIndex) private var cities: [CityPlan]
    @State private var editingPlace: PlaceBankItem?
    @State private var newPlaceCity: CityPlan?

    var body: some View {
        NavigationStack {
            List {
                if cities.isEmpty {
                    ContentUnavailableView("Nejdřív přidej město", systemImage: "building.2", description: Text("Banka míst je rozdělená podle měst."))
                }
                ForEach(cities) { city in
                    Section {
                        if city.sortedBankPlaces.isEmpty {
                            Text("Zatím žádná uložená místa")
                                .foregroundStyle(WaymintTheme.secondaryText)
                        }
                        ForEach(city.sortedBankPlaces) { place in
                            Button { editingPlace = place } label: {
                                PlaceBankRow(place: place)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { modelContext.delete(place) } label: {
                                    Label("Smazat", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(city.name)
                            Spacer()
                            Button { newPlaceCity = city } label: { Image(systemName: "plus.circle.fill") }
                        }
                    }
                }
            }
            .navigationTitle("Banka míst")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { dismiss() } }
            }
            .sheet(item: $newPlaceCity) { city in PlaceBankFormView(city: city, place: nil) }
            .sheet(item: $editingPlace) { place in
                if let city = place.city { PlaceBankFormView(city: city, place: place) }
            }
            .task { PlaceBankImporter.importExistingStops(from: cities, modelContext: modelContext) }
        }
    }
}

private struct PlaceBankRow: View {
    let place: PlaceBankItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.stopType.systemImage)
                .foregroundStyle(WaymintTheme.primaryGreen)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).font(.headline)
                if !place.mainReason.isEmpty { Text(place.mainReason).font(.subheadline).foregroundStyle(WaymintTheme.secondaryText).lineLimit(2) }
                Label(place.recommendedVisitDurationMinutes.minutesLabel, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(WaymintTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PlaceBankFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let city: CityPlan
    let place: PlaceBankItem?
    @State private var title = ""
    @State private var stopType = StopType.custom
    @State private var highlights = ""
    @State private var mainReason = ""
    @State private var note = ""
    @State private var duration = 45
    @State private var address = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @StateObject private var placeSearch = PlaceSearchService()
    @State private var mapPosition = MapCameraPosition.automatic

    var body: some View {
        NavigationStack {
            Form {
                Section("Vyhledat v Apple Mapách") {
                    HStack {
                        TextField("Název místa", text: $placeSearch.query)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit { searchPlaces() }
                        Button(action: searchPlaces) {
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        .disabled(placeSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if placeSearch.isSearching { ProgressView() }

                    ForEach(placeSearch.results.prefix(5), id: \.self) { result in
                        Button { selectCompletion(result) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(WaymintTheme.primaryText)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }

                    ForEach(placeSearch.mapItems) { result in
                        Button { selectMapItem(result.item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(WaymintTheme.primaryText)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(WaymintTheme.secondaryText)
                                }
                            }
                        }
                    }

                    if let errorMessage = placeSearch.errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(WaymintTheme.warning)
                    }
                }

                Section("Místo") {
                    TextField("Název", text: $title)
                    Picker("Typ", selection: $stopType) {
                        ForEach(StopType.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    TextField("Adresa", text: $address)
                    TextField("Zeměpisná šířka", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("Zeměpisná délka", text: $longitude).keyboardType(.numbersAndPunctuation)
                    if let coordinate = selectedCoordinate {
                        Map(position: $mapPosition) {
                            Marker(title.isEmpty ? "Vybrané místo" : title, coordinate: coordinate)
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
                    }
                }
                Section("Co tam chci vidět") {
                    TextField("Body, každý může být na novém řádku", text: $highlights, axis: .vertical).lineLimit(3...8)
                }
                Section("Proč tam jdu") {
                    TextField("Hlavní důvod", text: $mainReason, axis: .vertical).lineLimit(2...5)
                    TextField("Poznámky", text: $note, axis: .vertical).lineLimit(3...8)
                }
                Section("Doporučený čas") {
                    Stepper(duration.minutesLabel, value: $duration, in: 0...480, step: 5)
                }
                if let duplicatePlace {
                    Section {
                        Label("Toto místo už v bance existuje jako „\(duplicatePlace.title)“.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(WaymintTheme.warning)
                    }
                }
            }
            .navigationTitle(place == nil ? "Nové místo" : "Upravit místo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uložit", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicatePlace != nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let place else { return }
        title = place.title; stopType = place.stopType; highlights = place.highlights
        mainReason = place.mainReason; note = place.note; duration = place.recommendedVisitDurationMinutes
        address = place.address
        latitude = place.latitude.map { String($0) } ?? ""
        longitude = place.longitude.map { String($0) } ?? ""
        placeSearch.query = place.title
        updateMapPosition()
    }

    private func save() {
        let target = place ?? PlaceBankItem(title: title)
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.stopType = stopType; target.highlights = highlights; target.mainReason = mainReason; target.note = note
        target.recommendedVisitDurationMinutes = duration; target.address = address
        target.latitude = Double(latitude.replacingOccurrences(of: ",", with: "."))
        target.longitude = Double(longitude.replacingOccurrences(of: ",", with: "."))
        target.updatedAt = .now
        if place == nil { target.city = city; city.addBankPlace(target); modelContext.insert(target) }
        dismiss()
    }

    private var duplicatePlace: PlaceBankItem? {
        let parsedLatitude = Double(latitude.replacingOccurrences(of: ",", with: "."))
        let parsedLongitude = Double(longitude.replacingOccurrences(of: ",", with: "."))
        return city.sortedBankPlaces.first {
            $0.id != place?.id && PlaceBankDeduplicator.matches(
                title: title,
                address: address,
                latitude: parsedLatitude,
                longitude: parsedLongitude,
                place: $0
            )
        }
    }

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let latitude = Double(latitude.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitude.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func searchPlaces() {
        Task { await placeSearch.search() }
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        Task {
            guard let item = await placeSearch.resolve(completion) else { return }
            selectMapItem(item)
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        title = item.name ?? placeSearch.query
        address = formattedAddress(for: item)
        latitude = String(item.placemark.coordinate.latitude)
        longitude = String(item.placemark.coordinate.longitude)
        updateMapPosition()
        placeSearch.clear()
    }

    private func updateMapPosition() {
        guard let selectedCoordinate else { return }
        mapPosition = .region(MKCoordinateRegion(
            center: selectedCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    private func formattedAddress(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let street = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        return [street.isEmpty ? nil : street, placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
