import SwiftData
import SwiftUI

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var trip: TripPlan

    private let scheduleCalculator = ScheduleCalculator()

    private var stops: [TripStop] {
        trip.sortedStops
    }

    var body: some View {
        Group {
            if stops.isEmpty {
                EmptyStateView(
                    systemImage: "timeline.selection",
                    title: "Časová osa je prázdná",
                    message: "Přidej první zastávku a nastav čas příchodu, odchodu a délku návštěvy."
                )
            } else {
                List {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        VStack(spacing: 0) {
                            if index > 0 {
                                SegmentRow(
                                    segment: segment(before: stop),
                                    from: stops[index - 1],
                                    to: stop,
                                    showsClockTimes: trip.hasFixedStartTime
                                )
                            }

                            NavigationLink {
                                StopDetailView(stop: stop)
                            } label: {
                                TimelineStopRow(
                                    stop: stop,
                                    index: index + 1,
                                    isStart: index == 0,
                                    inboundSegment: index > 0 ? segment(before: stop) : nil,
                                    showsClockTimes: trip.hasFixedStartTime
                                )
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteStops)
                    .onMove(perform: moveStops)
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !stops.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private func segment(before stop: TripStop) -> TravelSegment? {
        trip.travelSegments?.first { $0.toStopID == stop.id }
    }

    private func deleteStops(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(stops[index])
        }
        normalizeStopOrder()
    }

    private func moveStops(from source: IndexSet, to destination: Int) {
        var reordered = stops
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, stop) in reordered.enumerated() {
            stop.sortIndex = index
        }
        scheduleCalculator.reconnectAndRecalculate(trip)
    }

    private func normalizeStopOrder() {
        for (index, stop) in stops.enumerated() {
            stop.sortIndex = index
        }
        scheduleCalculator.reconnectAndRecalculate(trip)
    }
}

private struct SegmentRow: View {
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
                    Text(travelDurationLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(WaymintTheme.darkGreen)
                }

                HStack(spacing: 8) {
                    Label {
                        Text(LocalizedStringKey(segment?.transportMode.title ?? "Přesun"))
                    } icon: {
                        Image(systemName: segment?.transportMode.systemImage ?? "arrow.right")
                    }
                    if let buffer = segment?.bufferMinutes, buffer > 0 {
                        Text(WaymintLocalization.format("+ %@ rezerva", buffer.minutesLabel))
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
        let duration = segment.plannedDurationMinutes
        guard (1...(12 * 60)).contains(duration) else { return 0 }
        return duration + min(max(0, segment.bufferMinutes), 180)
    }

    private var travelDurationLabel: String {
        guard let segment else { return totalTravelMinutes.minutesLabel }
        guard (1...(12 * 60)).contains(segment.plannedDurationMinutes) else {
            return WaymintLocalization.text("Zkontrolovat")
        }
        return totalTravelMinutes.minutesLabel
    }
}

private struct TimelineStopRow: View {
    let stop: TripStop
    let index: Int
    let isStart: Bool
    let inboundSegment: TravelSegment?
    let showsClockTimes: Bool

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
                }

            }
            .padding(12)
            .background(WaymintTheme.surface, in: RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WaymintTheme.cornerRadius)
                    .stroke(WaymintTheme.lightGreen, lineWidth: 1)
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

    private var primaryTimeLabel: String {
        if showsClockTimes {
            return isStart ? stop.plannedDeparture.waymintTime : stop.plannedArrival.waymintTime
        }
        return isStart ? WaymintLocalization.text("Start") : WaymintLocalization.format("Bod %d", index)
    }
}

#Preview {
    TimelineView(trip: TripPlan(title: "Centrum Helsinek"))
        .modelContainer(PreviewData.container())
}
