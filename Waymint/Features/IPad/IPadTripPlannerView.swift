import SwiftData
import SwiftUI

struct IPadTripPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: TripPlan

    @State private var selectedStopID: UUID?
    @State private var showingNewStop = false
    @State private var showingNewTicket = false
    @State private var showingTripSettings = false
    @State private var editingStop: TripStop?
    @State private var exportedWayFile: ExportedWayFile?
    @State private var exportErrorMessage = ""
    @State private var showingExportError = false
    @State private var sidePanelMode = IPadPlannerSidePanelMode.detail
    @AppStorage("waymintIPadTimelinePanelWidth") private var timelinePanelWidth = 332.0

    private let exportService = WaymintExportService()

    private var stops: [TripStop] {
        trip.sortedStops
    }

    private var selectedStop: TripStop? {
        if let selectedStopID, let stop = stops.first(where: { $0.id == selectedStopID }) {
            return stop
        }
        return stops.first
    }

    var body: some View {
        VStack(spacing: 0) {
            IPadTripPlannerHeader(trip: trip)

            if stops.isEmpty {
                IPadEmptyPlannerState {
                    showingNewStop = true
                }
            } else {
                GeometryReader { proxy in
                    let maximumTimelineWidth = min(560, max(300, proxy.size.width - 360))
                    let currentTimelineWidth = min(max(timelinePanelWidth, 280), maximumTimelineWidth)

                    HStack(spacing: 0) {
                        IPadTimelinePlannerColumn(
                            trip: trip,
                            stops: stops,
                        selectedStopID: $selectedStopID,
                        editingStop: $editingStop,
                        onAddStop: { showingNewStop = true },
                        onMoveStops: moveStops,
                        onDeleteStops: deleteStops
                    )
                        .frame(width: currentTimelineWidth)
                        .frame(maxHeight: .infinity)

                        IPadResizableDivider(
                            width: $timelinePanelWidth,
                            range: 280...maximumTimelineWidth
                        )

                        IPadPlannerSidePanel(
                            mode: sidePanelMode,
                            trip: trip,
                            stop: selectedStop,
                            onEditStop: { stop in editingStop = stop },
                            onAddTicket: { showingNewTicket = true }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(WaymintTheme.elevatedSurface)
        .navigationTitle("")
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

                Picker("Zobrazení", selection: $sidePanelMode) {
                    ForEach(IPadPlannerSidePanelMode.allCases) { mode in
                        Image(systemName: mode.systemImage)
                            .tag(mode)
                            .accessibilityLabel(mode.title)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button {
                    shareTrip()
                } label: {
                    Label("Sdílet cestu", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingNewStop = true
                } label: {
                    Label("Přidat zastávku", systemImage: "plus")
                }
            }
        }
        .onAppear {
            selectedStopID = selectedStopID ?? stops.first?.id
        }
        .onChange(of: trip.updatedAt) {
            if selectedStopID == nil || !stops.contains(where: { $0.id == selectedStopID }) {
                selectedStopID = stops.first?.id
            }
        }
        .sheet(isPresented: $showingNewStop) {
            StopFormView(trip: trip, stop: nil, nextSortIndex: trip.stopCount)
        }
        .sheet(isPresented: $showingNewTicket) {
            TicketFormView(trip: trip, stop: selectedStop)
        }
        .sheet(isPresented: $showingTripSettings) {
            if let city = trip.city {
                TripPlanFormView(city: city, trip: trip, nextSortIndex: city.tripPlanCount)
            }
        }
        .sheet(item: $editingStop) { stop in
            StopFormView(trip: trip, stop: stop, nextSortIndex: trip.stopCount)
        }
        .sheet(item: $exportedWayFile) { file in
            ShareSheet(activityItems: [
                WaymintFileActivityItem(url: file.url, title: "Waymint \(trip.title)")
            ])
        }
        .alert("Export se nepovedl", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func moveStops(from source: IndexSet, to destination: Int) {
        var reordered = stops
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, stop) in reordered.enumerated() {
            stop.sortIndex = index
        }
        trip.updatedAt = .now
    }

    private func deleteStops(at offsets: IndexSet) {
        let deletedIDs = offsets.compactMap { stops.indices.contains($0) ? stops[$0].id : nil }
        for index in offsets {
            guard stops.indices.contains(index) else { continue }
            modelContext.delete(stops[index])
        }

        let remainingStops = stops.filter { !deletedIDs.contains($0.id) }
        for (index, stop) in remainingStops.enumerated() {
            stop.sortIndex = index
        }
        if let selectedStopID, deletedIDs.contains(selectedStopID) {
            self.selectedStopID = remainingStops.first?.id
        }
        trip.updatedAt = .now
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

private struct IPadResizableDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var dragStartWidth: Double?
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(WaymintTheme.elevatedSurface)
                .frame(width: 18)

            RoundedRectangle(cornerRadius: 2)
                .fill(isDragging ? WaymintTheme.primaryGreen : WaymintTheme.secondaryText.opacity(0.35))
                .frame(width: isDragging ? 5 : 3, height: 46)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let proposedWidth = (dragStartWidth ?? width) + value.translation.width
                    width = min(max(proposedWidth, range.lowerBound), range.upperBound)
                    isDragging = true
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    isDragging = false
                }
        )
        .accessibilityLabel("Změnit šířku časové osy")
        .accessibilityHint("Tažením doleva nebo doprava upravíš šířku panelu.")
    }
}

private enum IPadPlannerSidePanelMode: String, CaseIterable, Identifiable {
    case detail
    case map
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detail: "Detail"
        case .map: "Mapa"
        case .both: "Oboje"
        }
    }

    var systemImage: String {
        switch self {
        case .detail: "sidebar.right"
        case .map: "map"
        case .both: "rectangle.split.2x1"
        }
    }
}

private struct IPadTripPlannerHeader: View {
    let trip: TripPlan

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip.date.waymintDate)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WaymintTheme.secondaryText)
                Text(trip.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(WaymintTheme.primaryText)
            }

            Spacer()

            Label(trip.scheduleLabel, systemImage: "clock")
            Label("\(trip.stopCount) míst", systemImage: "mappin.and.ellipse")
            Label("\(trip.ticketCount) vstupenek", systemImage: "ticket")
            StatusPill(trip.status.title, systemImage: "flag", tint: WaymintTheme.primaryGreen)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(WaymintTheme.surface)
    }
}

private struct IPadTimelinePlannerColumn: View {
    let trip: TripPlan
    let stops: [TripStop]
    @Binding var selectedStopID: UUID?
    @Binding var editingStop: TripStop?
    let onAddStop: () -> Void
    let onMoveStops: (IndexSet, Int) -> Void
    let onDeleteStops: (IndexSet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Časová osa", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                EditButton()
                Button(action: onAddStop) {
                    Image(systemName: "plus")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)

            List {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(spacing: 0) {
                        if index > 0 {
                                IPadTimelineSegmentRow(
                                    segment: segment(before: stop),
                                    from: stops[index - 1],
                                    to: stop,
                                    showsClockTimes: trip.hasFixedStartTime
                                )
                            }

                        IPadTimelineStopRow(
                            stop: stop,
                            index: index + 1,
                                    isStart: index == 0,
                                    isSelected: selectedStopID == stop.id,
                                    inboundSegment: index > 0 ? segment(before: stop) : nil,
                                    showsClockTimes: trip.hasFixedStartTime,
                                    onEdit: { editingStop = stop }
                                )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedStopID = stop.id }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                }
                .onMove(perform: onMoveStops)
                .onDelete(perform: onDeleteStops)
            }
            .listStyle(.plain)
        }
        .background(WaymintTheme.surface)
    }

    private func segment(before stop: TripStop) -> TravelSegment? {
        trip.travelSegments?.first { $0.toStopID == stop.id }
    }
}

private struct IPadTimelineSegmentRow: View {
    let segment: TravelSegment?
    let from: TripStop
    let to: TripStop
    let showsClockTimes: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(WaymintTheme.primaryGreen.opacity(0.26))
                    .frame(width: 3, height: 16)
                Image(systemName: segment?.transportMode.systemImage ?? "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WaymintTheme.primaryGreen)
                    .frame(width: 28, height: 28)
                    .background(WaymintTheme.lightGreen, in: Circle())
                Rectangle()
                    .fill(WaymintTheme.primaryGreen.opacity(0.26))
                    .frame(width: 3, height: 20)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Dojezd tam")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WaymintTheme.primaryText)
                    Spacer()
                    Text(totalTravelMinutes.minutesLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WaymintTheme.darkGreen)
                }

                HStack(spacing: 10) {
                    Label(segment?.transportMode.title ?? "Přesun", systemImage: segment?.transportMode.systemImage ?? "arrow.right")
                    Text(showsClockTimes ? "\(from.plannedDeparture.waymintTime) → \(to.plannedArrival.waymintTime)" : "Po předchozí zastávce")
                    if let buffer = segment?.bufferMinutes, buffer > 0 {
                        Text("+ \(buffer.minutesLabel) rezerva")
                    }
                }
                .font(.caption)
                .foregroundStyle(WaymintTheme.secondaryText)
            }
            .padding(12)
            .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
        }
        .padding(.leading, 4)
        .padding(.vertical, 2)
    }

    private var totalTravelMinutes: Int {
        guard let segment else {
            return max(0, Int(to.plannedArrival.timeIntervalSince(from.plannedDeparture) / 60))
        }
        return max(0, segment.plannedDurationMinutes + segment.bufferMinutes)
    }
}

private struct IPadTimelineStopRow: View {
    let stop: TripStop
    let index: Int
    let isStart: Bool
    let isSelected: Bool
    let inboundSegment: TravelSegment?
    let showsClockTimes: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: isStart ? "flag.checkered" : "\(index).circle.fill")
                    .font(isStart ? .headline : .title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(WaymintTheme.primaryGreen, in: Circle())
                Rectangle()
                    .fill(WaymintTheme.primaryGreen.opacity(0.28))
                    .frame(width: 3, height: 56)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(primaryTimeLabel)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(WaymintTheme.darkGreen)
                    if !isStart, showsClockTimes {
                        Text("- \(stop.plannedDeparture.waymintTime)")
                            .font(.subheadline)
                            .foregroundStyle(WaymintTheme.secondaryText)
                    }
                    Spacer()
                    StatusPill(isStart ? "Start" : stop.status.title, systemImage: isStart ? "flag.fill" : nil, tint: statusColor)
                }

                HStack {
                    Label(stop.title, systemImage: stop.stopType.systemImage)
                        .font(.headline)
                    Spacer()
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WaymintTheme.primaryGreen)
                            .frame(width: 28, height: 28)
                            .background(WaymintTheme.lightGreen.opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if !stop.mainReason.isEmpty {
                    Text(stop.mainReason)
                        .font(.subheadline)
                        .foregroundStyle(WaymintTheme.secondaryText)
                }

                HStack(spacing: 12) {
                    if isStart {
                        Label("Začátek cesty", systemImage: "location.fill")
                    } else {
                        Label("Na místě \(stop.plannedVisitDurationMinutes.minutesLabel)", systemImage: "timer")
                        Label("Dojezd \(inboundTravelMinutes.minutesLabel)", systemImage: "arrow.right")
                    }
                    Label(stop.isRequired ? "Povinná" : "Volitelná", systemImage: stop.isRequired ? "exclamationmark.circle" : "circle")
                    if stop.ticketCount > 0 {
                        Label("\(stop.ticketCount)", systemImage: "ticket")
                    }
                }
                .font(.caption)
                .foregroundStyle(WaymintTheme.secondaryText)
            }
            .padding(12)
            .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                    .stroke(isSelected ? WaymintTheme.primaryGreen.opacity(0.5) : WaymintTheme.lightGreen, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        if isStart {
            return WaymintTheme.primaryGreen
        }
        switch stop.status {
        case .completed:
            return WaymintTheme.success
        case .skipped:
            return WaymintTheme.secondaryText
        case .delayed:
            return WaymintTheme.warning
        case .active:
            return WaymintTheme.primaryGreen
        case .next, .planned:
            return WaymintTheme.darkGreen
        }
    }

    private var inboundTravelMinutes: Int {
        guard let inboundSegment else { return 0 }
        return max(0, inboundSegment.plannedDurationMinutes + inboundSegment.bufferMinutes)
    }

    private var primaryTimeLabel: String {
        if showsClockTimes {
            return isStart ? stop.plannedDeparture.waymintTime : stop.plannedArrival.waymintTime
        }
        return isStart ? "Start" : "Bod \(index)"
    }
}

private struct IPadDayBoardView: View {
    let trip: TripPlan
    @Binding var selectedStopID: UUID?

    private var stops: [TripStop] {
        trip.sortedStops
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Denní tabule", systemImage: "rectangle.split.3x1")
                    .font(.headline)
                Spacer()
                Text(trip.scheduleLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WaymintTheme.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        Button {
                            selectedStopID = stop.id
                        } label: {
                            IPadBoardStopBlock(
                                stop: stop,
                                index: index,
                                isSelected: selectedStopID == stop.id,
                                showsClockTimes: trip.hasFixedStartTime
                            )
                        }
                        .buttonStyle(.plain)

                        if index < stops.count - 1 {
                            IPadBoardTravelBlock(
                                segment: trip.travelSegments?.first { $0.toStopID == stops[index + 1].id },
                                from: stop,
                                to: stops[index + 1],
                                showsClockTimes: trip.hasFixedStartTime
                            )
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(14)
        .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
    }
}

private struct IPadBoardStopBlock: View {
    let stop: TripStop
    let index: Int
    let isSelected: Bool
    let showsClockTimes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titleLabel)
                    .font(.caption.weight(.bold))
                Spacer()
                Image(systemName: stop.stopType.systemImage)
            }
            Text(stop.title)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
            Text(subtitleLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .frame(width: blockWidth, height: 86, alignment: .topLeading)
        .padding(10)
        .background(isSelected ? WaymintTheme.darkGreen : WaymintTheme.primaryGreen, in: RoundedRectangle(cornerRadius: 12))
    }

    private var blockWidth: CGFloat {
        CGFloat(min(220, max(116, stop.plannedVisitDurationMinutes * 3)))
    }

    private var titleLabel: String {
        if showsClockTimes {
            return index == 0 ? "Start" : stop.plannedArrival.waymintTime
        }
        return index == 0 ? "Start" : "Bod \(index + 1)"
    }

    private var subtitleLabel: String {
        if showsClockTimes {
            return index == 0 ? stop.plannedDeparture.waymintTime : stop.plannedVisitDurationMinutes.minutesLabel
        }
        return index == 0 ? "Bez pevného času" : stop.plannedVisitDurationMinutes.minutesLabel
    }
}

private struct IPadBoardTravelBlock: View {
    let segment: TravelSegment?
    let from: TripStop
    let to: TripStop
    let showsClockTimes: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: segment?.transportMode.systemImage ?? "arrow.right")
                .font(.headline)
            Text(minutes.minutesLabel)
                .font(.caption.weight(.bold))
            Text(showsClockTimes ? "\(from.plannedDeparture.waymintTime) → \(to.plannedArrival.waymintTime)" : "Po předchozí")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(WaymintTheme.darkGreen)
        .frame(width: CGFloat(min(150, max(72, minutes * 3))), height: 86)
        .padding(10)
        .background(WaymintTheme.lightGreen.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private var minutes: Int {
        if let segment {
            return max(0, segment.plannedDurationMinutes + segment.bufferMinutes)
        }
        return max(0, Int(to.plannedArrival.timeIntervalSince(from.plannedDeparture) / 60))
    }
}

private struct IPadPlannerSidePanel: View {
    let mode: IPadPlannerSidePanelMode
    let trip: TripPlan
    let stop: TripStop?
    let onEditStop: (TripStop) -> Void
    let onAddTicket: () -> Void

    var body: some View {
        Group {
            switch mode {
            case .detail:
                IPadStopInspector(
                    trip: trip,
                    stop: stop,
                    onEditStop: onEditStop,
                    onAddTicket: onAddTicket
                )
            case .map:
                IPadPlannerMapPanel(trip: trip)
            case .both:
                HStack(spacing: 0) {
                    IPadPlannerMapPanel(trip: trip)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    IPadStopInspector(
                        trip: trip,
                        stop: stop,
                        onEditStop: onEditStop,
                        onAddTicket: onAddTicket
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WaymintTheme.surface)
    }
}

private struct IPadPlannerMapPanel: View {
    let trip: TripPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mapa", systemImage: "map")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            TripMapView(trip: trip)
        }
        .background(WaymintTheme.surface)
    }
}

private struct IPadStopInspector: View {
    let trip: TripPlan
    let stop: TripStop?
    let onEditStop: (TripStop) -> Void
    let onAddTicket: () -> Void

    var body: some View {
        Group {
            if let stop {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Detail místa")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WaymintTheme.secondaryText)
                                Text(stop.title)
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .foregroundStyle(WaymintTheme.primaryText)
                            }
                            Spacer()
                            Button {
                                onEditStop(stop)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }

                        IPadInspectorCard(title: "Čas", systemImage: "clock") {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(timeLabel(for: stop), systemImage: trip.hasFixedStartTime ? "calendar" : "timer")
                                Label("Na místě \(stop.plannedVisitDurationMinutes.minutesLabel)", systemImage: "timer")
                                if let segment = trip.travelSegments?.first(where: { $0.toStopID == stop.id }) {
                                    Label("Dojezd \(max(0, segment.plannedDurationMinutes + segment.bufferMinutes).minutesLabel)", systemImage: segment.transportMode.systemImage)
                                }
                            }
                            .font(.subheadline)
                        }

                        if !stop.note.isEmpty || !stop.mainReason.isEmpty {
                            IPadInspectorCard(title: "Poznámky", systemImage: "note.text") {
                                VStack(alignment: .leading, spacing: 10) {
                                    if !stop.mainReason.isEmpty {
                                        Text(stop.mainReason)
                                            .font(.headline)
                                    }
                                    if !stop.note.isEmpty {
                                        Text(stop.note)
                                            .font(.subheadline)
                                            .foregroundStyle(WaymintTheme.secondaryText)
                                    }
                                }
                            }
                        }

                        IPadInspectorCard(title: "Checklist", systemImage: "checklist") {
                            if stop.sortedChecklistItems.isEmpty {
                                Text("Checklist je prázdný.")
                                    .font(.subheadline)
                                    .foregroundStyle(WaymintTheme.secondaryText)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(stop.sortedChecklistItems) { item in
                                        Button {
                                            item.isDone.toggle()
                                        } label: {
                                            Label(item.title, systemImage: item.isDone ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(item.isDone ? WaymintTheme.primaryGreen : WaymintTheme.primaryText)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        IPadInspectorCard(title: "Vstupenky", systemImage: "ticket") {
                            VStack(alignment: .leading, spacing: 10) {
                                if stop.sortedTickets.isEmpty {
                                    Text("K tomuto místu nejsou vstupenky.")
                                        .font(.subheadline)
                                        .foregroundStyle(WaymintTheme.secondaryText)
                                } else {
                                    ForEach(stop.sortedTickets) { ticket in
                                        Label(ticket.title, systemImage: ticket.ticketType == .pdf ? "doc.richtext" : "ticket")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }

                                Button {
                                    onAddTicket()
                                } label: {
                                    Label("Přidat vstupenku", systemImage: "plus")
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                IPadEmptyPanel(
                    systemImage: "mappin.circle",
                    title: "Vyber zastávku",
                    message: "Tady se ukáže poznámka, checklist a vstupenky k vybranému místu."
                )
            }
        }
        .background(WaymintTheme.surface)
    }

    private func timeLabel(for stop: TripStop) -> String {
        guard trip.hasFixedStartTime else {
            if trip.sortedStops.first?.id == stop.id {
                return "Start bez pevného času"
            }
            return "Pořadí v cestě"
        }
        return "\(stop.plannedArrival.waymintTime)-\(stop.plannedDeparture.waymintTime)"
    }
}

private struct IPadInspectorCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(WaymintTheme.primaryText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WaymintTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
    }
}

private struct IPadEmptyPlannerState: View {
    let onAddStop: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(WaymintTheme.primaryGreen)
            Text("Začni prvním bodem")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("První zastávka je start. Potom přidávej další místa a Waymint z nich poskládá přehlednou časovou osu i mapu.")
                .font(.body)
                .foregroundStyle(WaymintTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button(action: onAddStop) {
                Label("Přidat první zastávku", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    func minWidth(_ width: CGFloat, alignment: Alignment = .center) -> some View {
        frame(minWidth: width, alignment: alignment)
    }
}

#Preview {
    NavigationStack {
        IPadTripPlannerView(trip: TripPlan(title: "Centrum"))
    }
    .modelContainer(PreviewData.container())
}
