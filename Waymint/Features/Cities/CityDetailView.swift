import SwiftData
import SwiftUI
internal import Photos
import UIKit
import UniformTypeIdentifiers

struct CityDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var city: CityPlan

    @State private var showingNewTrip = false
    @State private var editingTrip: TripPlan?
    @State private var importingTrip = false
    @State private var importErrorMessage = ""
    @State private var showingImportError = false

    private let exportService = WaymintExportService()

    private var trips: [TripPlan] {
        city.sortedTripPlans.sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.date < rhs.date
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    var body: some View {
        List {
            CityLandingSection(city: city)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if trips.isEmpty {
                EmptyStateView(
                    systemImage: "calendar.badge.plus",
                    title: "Zatím žádný plán",
                    message: "Vytvoř denní trasu a začni skládat zastávky podle času."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(trips) { trip in
                    NavigationLink {
                        TripOverviewView(trip: trip)
                    } label: {
                        TripCardView(trip: trip)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingTrip = trip
                        } label: {
                            Label("Upravit", systemImage: "pencil")
                        }
                        .tint(WaymintTheme.primaryGreen)

                        Button {
                            duplicate(trip)
                        } label: {
                            Label("Duplikovat", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: deleteTrips)
                .onMove(perform: moveTrips)
            }
        }
        .listStyle(.plain)
        .navigationTitle(city.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !trips.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button {
                        showingNewTrip = true
                    } label: {
                        Label("Přidat plán", systemImage: "plus")
                    }

                    Menu {
                        if !trips.isEmpty {
                            NavigationLink {
                                CityTripsMapView(city: city)
                            } label: {
                                Label("Mapa města", systemImage: "map")
                            }
                            NavigationLink {
                                CityWrappedView(city: city)
                            } label: {
                                Label("Wrapped", systemImage: "sparkles")
                            }
                        }
                        Button { importingTrip = true } label: {
                            Label("Importovat .way", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Další akce", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewTrip) {
            TripPlanFormView(city: city, trip: nil, nextSortIndex: trips.count)
        }
        .sheet(item: $editingTrip) { trip in
            TripPlanFormView(city: city, trip: trip, nextSortIndex: trips.count)
        }
        .fileImporter(
            isPresented: $importingTrip,
            allowedContentTypes: [.waymintRouteFile, .json],
            allowsMultipleSelection: false
        ) { result in
            importTrip(from: result)
        }
        .alert("Import se nepovedl", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
    }

    private func moveTrips(from source: IndexSet, to destination: Int) {
        var reordered = trips
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, trip) in reordered.enumerated() {
            trip.sortIndex = index
        }
    }

    private func duplicate(_ trip: TripPlan) {
        let copy = TripPlan(
            title: "\(trip.title) kopie",
            date: trip.date,
            startTime: trip.startTime,
            hasFixedStartTime: trip.hasFixedStartTime,
            status: .draft,
            sortIndex: trips.count,
            landingTitle: trip.landingTitle,
            landingSubtitle: trip.landingSubtitle,
            photoAlbumLocalIdentifier: trip.photoAlbumLocalIdentifier,
            photoAlbumTitle: trip.photoAlbumTitle,
            note: trip.note
        )
        for stop in trip.sortedStops {
            let stopCopy = TripStop(
                title: stop.title,
                stopType: stop.stopType,
                status: .planned,
                plannedArrival: stop.plannedArrival,
                plannedDeparture: stop.plannedDeparture,
                plannedVisitDurationMinutes: stop.plannedVisitDurationMinutes,
                address: stop.address,
                latitude: stop.latitude,
                longitude: stop.longitude,
                note: stop.note,
                mainReason: stop.mainReason,
                isRequired: stop.isRequired,
                sortIndex: stop.sortIndex
            )
            copy.addStop(stopCopy)
        }
        city.addTripPlan(copy)
    }

    private func importTrip(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let importedTrip = try exportService.importTrip(from: url, nextSortIndex: trips.count)
            city.addTripPlan(importedTrip)
            city.updatedAt = .now
        } catch {
            importErrorMessage = error.localizedDescription
            showingImportError = true
        }
    }
}

private extension UTType {
    static var waymintRouteFile: UTType {
        UTType(filenameExtension: "way") ?? .json
    }
}

private struct CityLandingSection: View {
    let city: CityPlan

    private var albumIdentifier: String? {
        city.sortedTripPlans.first { $0.photoAlbumLocalIdentifier != nil }?.photoAlbumLocalIdentifier
    }

    var body: some View {
        ZStack {
            if let albumIdentifier {
                AlbumHeroBackground(albumIdentifier: albumIdentifier)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(albumIdentifier == nil ? 0 : 0.18),
                    Color.black.opacity(albumIdentifier == nil ? 0 : 0.56)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(city.country.isEmpty ? WaymintLocalization.text("Cesta") : WaymintLocalization.countryName(city.country).uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.68))
                        Text(city.landingTitle.isEmpty ? city.name : city.landingTitle)
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                Text(city.landingSubtitle.isEmpty ? WaymintLocalization.format("Naplánuj dny, místa, přesuny a vstupenky pro %@.", city.name) : city.landingSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(18)
        }
        .frame(minHeight: 170)
        .background(
            LinearGradient(
                colors: [WaymintTheme.darkGreen, WaymintTheme.primaryGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

private struct AlbumHeroBackground: View {
    let albumIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.7)
            }
        }
        .task(id: albumIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumIdentifier], options: nil)
        guard let collection = collections.firstObject else { return }
        let options = PHFetchOptions()
        options.fetchLimit = 1
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        guard let asset = PHAsset.fetchAssets(in: collection, options: options).firstObject else { return }

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 900, height: 520),
            contentMode: .aspectFill,
            options: nil
        ) { result, _ in
            Task { @MainActor in
                image = result
            }
        }
    }
}

private struct TripCardView: View {
    let trip: TripPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.title)
                        .font(.headline)
                    Text(trip.date.waymintDate)
                        .font(.subheadline)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
                Spacer()
                StatusPill(trip.status.title, tint: WaymintTheme.primaryGreen)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        CityDetailView(city: CityPlan(name: "Helsinky", country: "Finsko"))
    }
    .modelContainer(PreviewData.container())
}
