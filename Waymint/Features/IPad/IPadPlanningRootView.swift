import SwiftData
import SwiftUI

struct IPadPlanningRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CityPlan.sortIndex) private var cities: [CityPlan]

    @State private var selectedCityID: UUID?
    @State private var selectedTripID: UUID?
    @State private var showingNewCity = false
    @State private var showingNewTrip = false
    @State private var showingSettings = false
    @State private var editingCity: CityPlan?
    @State private var editingTrip: TripPlan?
    @State private var cityPendingDeletion: CityPlan?
    @State private var showingDeleteCityConfirmation = false
    @State private var showingPlaceBank = false
    @AppStorage("waymintPlaceBankEnabled") private var placeBankEnabled = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var allTrips: [TripPlan] {
        cities.flatMap { city in
            city.sortedTripPlans
        }
    }

    private var selectedCity: CityPlan? {
        if let selectedTrip {
            return selectedTrip.city
        }
        if let selectedCityID, let city = cities.first(where: { $0.id == selectedCityID }) {
            return city
        }
        return cities.first
    }

    private var selectedTrip: TripPlan? {
        if let selectedTripID, let trip = allTrips.first(where: { $0.id == selectedTripID }) {
            return trip
        }
        return allTrips.first
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedTripID) {
                ForEach(cities) { city in
                    Section {
                        ForEach(sortedTrips(for: city)) { trip in
                            IPadTripRow(trip: trip)
                                .tag(trip.id)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingTrip = trip
                                    } label: {
                                        Label("Upravit", systemImage: "slider.horizontal.3")
                                    }
                                    .tint(WaymintTheme.primaryGreen)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteTrip(trip)
                                    } label: {
                                        Label("Smazat cestu", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            deleteTrips(in: city, at: offsets)
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city.name)
                                    .font(.headline)
                                Text(city.country.isEmpty
                                     ? WaymintLocalization.format("%d cest", city.tripPlanCount)
                                     : WaymintLocalization.format("%@ · %d cest", WaymintLocalization.countryName(city.country), city.tripPlanCount))
                                    .font(.caption)
                                    .foregroundStyle(WaymintTheme.secondaryText)
                            }
                            Spacer()
                            Button {
                                selectedCityID = city.id
                                showingNewTrip = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    editingCity = city
                                } label: {
                                    Label("Upravit město", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    cityPendingDeletion = city
                                    showingDeleteCityConfirmation = true
                                } label: {
                                    Label("Smazat město", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .textCase(nil)
                        .padding(.top, 8)
                    }
                }
                if cities.isEmpty {
                    Section {
                        Button {
                            showingNewCity = true
                        } label: {
                            Label("Přidat první město", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Waymint")
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 520)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !cities.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if placeBankEnabled {
                            Button { showingPlaceBank = true } label: {
                                Label("Banka míst", systemImage: "square.grid.2x2")
                            }
                        }
                        Button {
                            showingSettings = true
                        } label: {
                            Label("Nastavení", systemImage: "gearshape")
                        }

                        Button {
                            showingNewCity = true
                        } label: {
                            Label("Přidat město", systemImage: "plus")
                        }
                    }
                }
            }
        } detail: {
            if let selectedTrip {
                IPadTripPlannerView(
                    trip: selectedTrip,
                    columnVisibility: $columnVisibility
                )
            } else if let selectedCity {
                IPadEmptyPanel(
                    systemImage: "calendar.badge.plus",
                    title: selectedCity.name,
                    message: "Vyber cestu vlevo nebo vytvoř nový denní plán."
                )
            } else {
                IPadEmptyPanel(
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    title: "Waymint",
                    message: "Přidej město a potom do něj poskládej jednotlivé cesty."
                )
            }
        }
        .onAppear {
            if selectedTripID == nil {
                selectedTripID = allTrips.first?.id
            }
            if selectedCityID == nil {
                selectedCityID = selectedCity?.id
            }
        }
        .onChange(of: selectedTripID) {
            selectedCityID = selectedTrip?.city?.id ?? selectedCityID
        }
        .sheet(isPresented: $showingNewCity) {
            CityFormView(city: nil, nextSortIndex: cities.count)
        }
        .sheet(isPresented: $showingNewTrip) {
            if let selectedCity {
                TripPlanFormView(city: selectedCity, trip: nil, nextSortIndex: selectedCity.tripPlanCount)
            }
        }
        .sheet(item: $editingCity) { city in
            CityFormView(city: city, nextSortIndex: cities.count)
        }
        .sheet(item: $editingTrip) { trip in
            if let city = trip.city {
                TripPlanFormView(city: city, trip: trip, nextSortIndex: city.tripPlanCount)
            }
        }
        .sheet(isPresented: $showingSettings) {
            AppSettingsView()
        }
        .sheet(isPresented: $showingPlaceBank) { PlaceBankView() }
        .confirmationDialog(
            "Smazat město \(cityPendingDeletion?.name ?? "")?",
            isPresented: $showingDeleteCityConfirmation,
            titleVisibility: .visible
        ) {
            Button("Smazat město i všechny jeho cesty", role: .destructive) {
                if let cityPendingDeletion {
                    deleteCity(cityPendingDeletion)
                }
                cityPendingDeletion = nil
            }
            Button("Zrušit", role: .cancel) {
                cityPendingDeletion = nil
            }
        } message: {
            Text("Tuto akci nelze vrátit zpět.")
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sortedTrips(for city: CityPlan) -> [TripPlan] {
        city.sortedTripPlans
    }

    private func deleteTrip(_ trip: TripPlan) {
        if selectedTripID == trip.id {
            selectedTripID = allTrips.first { $0.id != trip.id }?.id
        }
        modelContext.delete(trip)
    }

    private func deleteTrips(in city: CityPlan, at offsets: IndexSet) {
        let trips = sortedTrips(for: city)
        for index in offsets {
            guard trips.indices.contains(index) else { continue }
            deleteTrip(trips[index])
        }
    }

    private func deleteCity(_ city: CityPlan) {
        let remainingCities = cities.filter { $0.id != city.id }
        let remainingTrips = remainingCities.flatMap(\.sortedTripPlans)

        if selectedCityID == city.id || selectedTrip?.city?.id == city.id {
            selectedCityID = remainingCities.first?.id
            selectedTripID = remainingTrips.first?.id
        }

        modelContext.delete(city)

        for (index, remainingCity) in remainingCities.enumerated() {
            remainingCity.sortIndex = index
        }
    }
}

private struct IPadTripRow: View {
    let trip: TripPlan

    private var issueCount: Int {
        TripReadinessChecker.issues(for: trip).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trip.title)
                    .font(.headline)
                    .foregroundStyle(WaymintTheme.primaryText)
                Spacer()
                if issueCount > 0 {
                    Label("\(issueCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WaymintTheme.warning)
                        .accessibilityLabel(WaymintLocalization.format("%d problémů před cestou", issueCount))
                } else if trip.stopCount > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WaymintTheme.success)
                        .accessibilityLabel("Cesta je připravená")
                }
                StatusPill(trip.status.title, tint: WaymintTheme.primaryGreen)
            }
            Text("\(trip.date.waymintDate) · \(trip.scheduleLabel)")
                .font(.subheadline)
                .foregroundStyle(WaymintTheme.secondaryText)
            HStack(spacing: 10) {
                Label("\(trip.stopCount)", systemImage: "mappin")
                Label(trip.hasFixedStartTime ? trip.approximateDurationMinutes.minutesLabel : trip.scheduleLabel, systemImage: "clock")
                if trip.totalTicketCount > 0 {
                    Label("\(trip.totalTicketCount)", systemImage: "ticket")
                }
            }
            .font(.caption)
            .foregroundStyle(WaymintTheme.secondaryText)
        }
        .padding(.vertical, 6)
    }
}

struct IPadEmptyPanel: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(WaymintTheme.primaryGreen)
            Text(LocalizedStringKey(title))
                .font(.system(.title, design: .rounded).weight(.bold))
            Text(LocalizedStringKey(message))
                .font(.body)
                .foregroundStyle(WaymintTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WaymintTheme.elevatedSurface)
    }
}

#Preview {
    IPadPlanningRootView()
        .modelContainer(PreviewData.container())
}
