import SwiftData
import SwiftUI

struct CitiesOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CityPlan.sortIndex) private var cities: [CityPlan]

    @State private var searchText = ""
    @State private var showingNewCity = false
    @State private var showingSettings = false
    @State private var editingCity: CityPlan?
    @State private var showingPlaceBank = false
    @AppStorage("waymintPlaceBankEnabled") private var placeBankEnabled = false

    private var filteredCities: [CityPlan] {
        guard !searchText.isEmpty else { return cities }
        return cities.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.country.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cities.isEmpty {
                    VStack(spacing: 20) {
                        WaymintStartCard(cityCount: 0)
                        Button {
                            showingNewCity = true
                        } label: {
                            Label("Vytvořit první město", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        Section {
                            WaymintStartCard(cityCount: cities.count)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                        }

                        ForEach(filteredCities) { city in
                            NavigationLink {
                                CityDetailView(city: city)
                            } label: {
                                CityCardView(city: city)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingCity = city
                                } label: {
                                    Label("Upravit", systemImage: "pencil")
                                }
                                .tint(WaymintTheme.primaryGreen)
                            }
                        }
                        .onDelete(perform: deleteCities)
                        .onMove(perform: moveCities)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Waymint")
            .searchable(text: $searchText, prompt: "Hledat město")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !cities.isEmpty && searchText.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Menu {
                            if placeBankEnabled {
                                Button { showingPlaceBank = true } label: {
                                    Label("Banka míst", systemImage: "square.grid.2x2")
                                }
                            }
                            Button { showingSettings = true } label: {
                                Label("Nastavení", systemImage: "gearshape")
                            }
                        } label: {
                            Label("Další akce", systemImage: "ellipsis.circle")
                        }

                        Button {
                            showingNewCity = true
                        } label: {
                            Label("Přidat město", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewCity) {
                CityFormView(city: nil, nextSortIndex: cities.count)
            }
            .sheet(item: $editingCity) { city in
                CityFormView(city: city, nextSortIndex: cities.count)
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView()
            }
            .sheet(isPresented: $showingPlaceBank) { PlaceBankView() }
        }
    }

    private func deleteCities(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredCities[index])
        }
        normalizeCityOrder()
    }

    private func moveCities(from source: IndexSet, to destination: Int) {
        guard searchText.isEmpty else { return }
        var reordered = cities
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, city) in reordered.enumerated() {
            city.sortIndex = index
        }
    }

    private func normalizeCityOrder() {
        for (index, city) in cities.sorted(by: { $0.sortIndex < $1.sortIndex }).enumerated() {
            city.sortIndex = index
        }
    }
}

private struct WaymintStartCard: View {
    let cityCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(localizedCount(cityCount, one: "%d město", few: "%d města", many: "%d měst"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Waymint")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Tvoje cesty, vstupenky, přesuny a místa v jednom klidném plánu.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(
                colors: [WaymintTheme.darkGreen, WaymintTheme.primaryGreen, Color(red: 0.08, green: 0.17, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private func localizedCount(_ count: Int, one: String, few: String, many: String) -> String {
        let key = count == 1 ? one : ((2...4).contains(count) ? few : many)
        return WaymintLocalization.format(key, count)
    }
}

private struct CityCardView: View {
    let city: CityPlan

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                    .fill(WaymintTheme.lightGreen)
                    .frame(width: 58, height: 58)
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(WaymintTheme.darkGreen)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(city.name)
                    .font(.headline)
                    .foregroundStyle(WaymintTheme.primaryText)

                Text(WaymintLocalization.countryName(city.country))
                    .font(.subheadline)
                    .foregroundStyle(WaymintTheme.secondaryText)

                HStack {
                    StatusPill(localizedPlanCount, systemImage: "calendar")
                    if let nextPlan = city.sortedTripPlans.sorted(by: { $0.date < $1.date }).first {
                        Text(nextPlan.date.waymintDate)
                            .font(.caption)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var localizedPlanCount: String {
        let count = city.tripPlanCount
        let key = count == 1 ? "%d plán" : ((2...4).contains(count) ? "%d plány" : "%d plánů")
        return WaymintLocalization.format(key, count)
    }
}

#Preview {
    CitiesOverviewView()
        .modelContainer(PreviewData.container())
}
