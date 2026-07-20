import SwiftData
import SwiftUI
internal import Photos

struct TripPlanFormView: View {
    @Environment(\.dismiss) private var dismiss

    let city: CityPlan
    let trip: TripPlan?
    let nextSortIndex: Int

    @State private var title = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var hasFixedStartTime = true
    @State private var status = TripPlanStatus.draft
    @State private var landingTitle = ""
    @State private var landingSubtitle = ""
    @State private var photoAlbumLocalIdentifier: String?
    @State private var photoAlbumTitle: String?
    @State private var showingAlbumPicker = false
    @State private var note = ""
    @State private var delayResponseStrategy = DelayResponseStrategy.shiftEverything
    private let scheduleCalculator = ScheduleCalculator()

    var body: some View {
        NavigationStack {
            Form {
                Section("Plán") {
                    TextField("Název", text: $title)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Toggle("Pevný začátek", isOn: $hasFixedStartTime)
                    if hasFixedStartTime {
                        DatePicker("Začátek", selection: $startTime, displayedComponents: .hourAndMinute)
                    } else {
                        Label("Cesta začne až ve chvíli, kdy ji spustíš. Waymint potom bude ukazovat reálnou délku cesty.", systemImage: "timer")
                            .font(.footnote)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    Picker("Stav", selection: $status) {
                        ForEach(TripPlanStatus.allCases) { status in
                            Text(LocalizedStringKey(status.title)).tag(status)
                        }
                    }
                    if let trip, trip.stopCount > 0 {
                        Text("Změna data nebo začátku posune všechny už vytvořené zastávky o stejný rozdíl.")
                            .font(.footnote)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                }

                Section("Úvodní stránka") {
                    TextField("Nadpis", text: $landingTitle)
                    TextField("Krátký popis", text: $landingSubtitle, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("Při zpoždění") {
                    Picker("Reakce aplikace", selection: $delayResponseStrategy) {
                        ForEach(DelayResponseStrategy.allCases) { strategy in
                            Text(LocalizedStringKey(strategy.title)).tag(strategy)
                        }
                    }
                    Text("Pevné časy označené u trajektu, vlaku nebo rezervace se neposouvají.")
                        .font(.caption)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                Section("Album z Apple Photos") {
                    Button {
                        showingAlbumPicker = true
                    } label: {
                        Label(photoAlbumTitle ?? "Vybrat album", systemImage: "photo.on.rectangle.angled")
                    }

                    if photoAlbumTitle != nil {
                        Button(role: .destructive) {
                            photoAlbumLocalIdentifier = nil
                            photoAlbumTitle = nil
                        } label: {
                            Label("Odpojit album", systemImage: "xmark.circle")
                        }
                    }
                }

                Section("Poznámka") {
                    TextField("Volitelná poznámka", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(trip == nil ? "Nový plán" : "Upravit plán")
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
            .onChange(of: hasFixedStartTime) { _, isFixed in
                if isFixed, let actualStartedAt = trip?.actualStartedAt {
                    startTime = actualStartedAt
                }
            }
            .sheet(isPresented: $showingAlbumPicker) {
                PhotoAlbumPickerView { album in
                    photoAlbumLocalIdentifier = album.localIdentifier
                    photoAlbumTitle = album.localizedTitle ?? "Album"
                }
            }
        }
    }

    private func load() {
        guard let trip else { return }
        title = trip.title
        date = trip.date
        startTime = trip.startTime
        hasFixedStartTime = trip.hasFixedStartTime
        status = trip.status
        landingTitle = trip.landingTitle
        landingSubtitle = trip.landingSubtitle
        photoAlbumLocalIdentifier = trip.photoAlbumLocalIdentifier
        photoAlbumTitle = trip.photoAlbumTitle
        note = trip.note
        delayResponseStrategy = trip.delayResponseStrategy
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStartTime = Self.combinedDate(date: date, time: startTime)

        if let trip {
            shiftTimelineIfNeeded(for: trip)
            trip.title = trimmedTitle
            trip.date = date
            trip.startTime = normalizedStartTime
            trip.hasFixedStartTime = hasFixedStartTime
            trip.status = status
            trip.landingTitle = landingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.landingSubtitle = landingSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            trip.photoAlbumLocalIdentifier = photoAlbumLocalIdentifier
            trip.photoAlbumTitle = photoAlbumTitle
            trip.note = note
            trip.delayResponseStrategy = delayResponseStrategy
            trip.updatedAt = .now
        } else {
            let newTrip = TripPlan(
                title: trimmedTitle,
                date: date,
                startTime: normalizedStartTime,
                hasFixedStartTime: hasFixedStartTime,
                delayResponseStrategy: delayResponseStrategy,
                status: status,
                sortIndex: nextSortIndex,
                landingTitle: landingTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                landingSubtitle: landingSubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                photoAlbumLocalIdentifier: photoAlbumLocalIdentifier,
                photoAlbumTitle: photoAlbumTitle,
                note: note
            )
            city.addTripPlan(newTrip)
        }

        dismiss()
    }

    private func shiftTimelineIfNeeded(for trip: TripPlan) {
        guard hasFixedStartTime else { return }
        let oldAnchor: Date
        if trip.hasFixedStartTime {
            oldAnchor = Self.combinedDate(date: trip.date, time: trip.startTime)
        } else {
            oldAnchor = trip.sortedStops.first?.plannedArrival ?? Self.combinedDate(date: trip.date, time: trip.startTime)
        }
        let newAnchor = Self.combinedDate(date: date, time: startTime)
        guard abs(newAnchor.timeIntervalSince(oldAnchor)) >= 60 else { return }
        scheduleCalculator.recalculateTrip(trip, anchor: newAnchor)
    }

    private static func combinedDate(date: Date, time: Date) -> Date {
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        return Calendar.current.date(from: dateComponents) ?? date
    }
}

#Preview {
    TripPlanFormView(city: CityPlan(name: "Helsinky"), trip: nil, nextSortIndex: 0)
        .modelContainer(PreviewData.container())
}
