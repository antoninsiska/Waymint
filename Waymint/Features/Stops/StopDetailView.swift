import MapKit
import SwiftData
import SwiftUI
import UIKit

struct StopDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var stop: TripStop

    @State private var showingEdit = false
    @State private var newChecklistTitle = ""
    @State private var showingTicketForm = false
    @State private var selectedTicket: TicketItem?
    @State private var editingTicket: TicketItem?
    @State private var previewURL: URL?
    @State private var showingFilePreview = false
    @State private var ticketToDelete: TicketItem?
    private let ticketStorage = TicketStorageService()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(stop.stopType.title, systemImage: stop.stopType.systemImage)
                        Spacer()
                        StatusPill(stop.status.title)
                    }
                    .font(.subheadline)

                    Text(stop.title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(WaymintTheme.darkGreen)

                    Text(scheduleText)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
                .padding(.vertical, 8)
            }

            if !stop.mainReason.isEmpty {
                Section("Proc sem jdu") {
                    Text(stop.mainReason)
                        .font(.headline)
                }
            }

            Section("Checklist") {
                ForEach(stop.sortedChecklistItems) { item in
                    ChecklistItemRow(item: item)
                }
                .onDelete(perform: deleteChecklistItems)

                HStack {
                    TextField("Pridat polozku", text: $newChecklistTitle)
                    Button {
                        addChecklistItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Misto") {
                if !stop.address.isEmpty {
                    Label(stop.address, systemImage: "location")
                }

                if let latitude = stop.latitude, let longitude = stop.longitude {
                    Map(initialPosition: .region(region(latitude: latitude, longitude: longitude))) {
                        Annotation(stop.title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(WaymintTheme.primaryGreen)
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))

                    Button {
                        openInMaps(latitude: latitude, longitude: longitude)
                    } label: {
                        Label("Otevrit v Apple Maps", systemImage: "map")
                    }
                } else {
                    Text("Souradnice zatim nejsou vyplnene.")
                        .foregroundStyle(WaymintTheme.secondaryText)
                }
            }

            if !stop.note.isEmpty {
                Section("Poznamka") {
                    Text(stop.note)
                }
            }

            Section("Vstupenky") {
                if stop.ticketCount == 0 {
                    Text("Zatim zadna vstupenka.")
                        .foregroundStyle(WaymintTheme.secondaryText)
                } else {
                    ForEach(stop.sortedTickets) { ticket in
                        TicketRowView(
                            ticket: ticket,
                            onOpen: { open(ticket) },
                            onEdit: { editingTicket = ticket },
                            onDelete: { ticketToDelete = ticket }
                        )
                    }
                    .onDelete(perform: deleteTickets)
                }

                Button {
                    showingTicketForm = true
                } label: {
                    Label("Pridat textovou vstupenku", systemImage: "ticket")
                }
            }
        }
        .navigationTitle("Zastavka")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEdit = true
                } label: {
                    Label("Upravit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let trip = stop.tripPlan {
                StopFormView(trip: trip, stop: stop, nextSortIndex: trip.stopCount)
            }
        }
        .sheet(isPresented: $showingTicketForm) {
            TicketFormView(trip: stop.tripPlan, stop: stop)
        }
        .sheet(item: $selectedTicket) { ticket in
            NavigationStack {
                TicketDetailView(
                    ticket: ticket,
                    onOpenFile: { open(ticket) },
                    onEdit: {
                        selectedTicket = nil
                        editingTicket = ticket
                    },
                    onDelete: {
                        selectedTicket = nil
                        ticketToDelete = ticket
                    }
                )
            }
        }
        .sheet(item: $editingTicket) { ticket in
            TicketFormView(trip: ticket.tripPlan, stop: ticket.stop, ticket: ticket)
        }
        .sheet(isPresented: $showingFilePreview) {
            if let previewURL {
                TicketFilePreview(url: previewURL)
            }
        }
        .confirmationDialog("Smazat vstupenku?", isPresented: deleteConfirmationBinding, titleVisibility: .visible) {
            Button("Smazat", role: .destructive) {
                if let ticketToDelete {
                    ticketStorage.deleteLocalFile(at: ticketToDelete.localFilePath)
                    modelContext.delete(ticketToDelete)
                }
                selectedTicket = nil
                editingTicket = nil
                ticketToDelete = nil
            }
            Button("Zrusit", role: .cancel) {
                ticketToDelete = nil
            }
        }
    }

    private var scheduleText: String {
        guard stop.tripPlan?.hasFixedStartTime ?? true else {
            if stop.tripPlan?.sortedStops.first?.id == stop.id {
                return "Start bez pevného času"
            }
            return "Na místě \(stop.plannedVisitDurationMinutes.minutesLabel)"
        }
        return "\(stop.plannedArrival.waymintTime)-\(stop.plannedDeparture.waymintTime) · \(stop.plannedVisitDurationMinutes.minutesLabel)"
    }

    private func addChecklistItem() {
        let trimmed = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop.addChecklistItem(StopChecklistItem(title: trimmed, sortIndex: stop.checklistItemCount))
        newChecklistTitle = ""
    }

    private func deleteChecklistItems(at offsets: IndexSet) {
        let items = stop.sortedChecklistItems
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func deleteTickets(at offsets: IndexSet) {
        let tickets = stop.sortedTickets
        for index in offsets {
            ticketStorage.deleteLocalFile(at: tickets[index].localFilePath)
            modelContext.delete(tickets[index])
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { ticketToDelete != nil },
            set: { if !$0 { ticketToDelete = nil } }
        )
    }

    private func open(_ ticket: TicketItem) {
        if let localFilePath = ticket.localFilePath {
            previewURL = URL(filePath: localFilePath)
            showingFilePreview = true
            return
        }
        if ticket.ticketType == .link,
           let externalURLString = ticket.externalURLString ?? ticket.code,
           let url = URL(string: externalURLString) {
            UIApplication.shared.open(url)
            return
        }
        selectedTicket = ticket
    }

    private func openInMaps(latitude: Double, longitude: Double) {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = stop.title
        item.openInMaps()
    }

    private func region(latitude: Double, longitude: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}

private struct ChecklistItemRow: View {
    @Bindable var item: StopChecklistItem

    var body: some View {
        Button {
            item.isDone.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? WaymintTheme.success : WaymintTheme.secondaryText)

                Text(item.title)
                    .foregroundStyle(item.isDone ? WaymintTheme.secondaryText : WaymintTheme.primaryText)
                    .strikethrough(item.isDone)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.isDone ? "Hotovo" : "Nedokonceno")
    }
}

#Preview {
    NavigationStack {
        StopDetailView(stop: TripStop(title: "Ateneum", mainReason: "Klasicka finska malba"))
    }
    .modelContainer(PreviewData.container())
}
