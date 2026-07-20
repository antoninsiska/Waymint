import Foundation

struct ScheduleCalculator {
    func plannedDeparture(arrival: Date, visitDurationMinutes: Int) -> Date {
        arrival.addingTimeInterval(TimeInterval(max(0, visitDurationMinutes) * 60))
    }

    func recommendedDeparture(nextArrival: Date, travelDurationMinutes: Int, bufferMinutes: Int = 0) -> Date {
        let totalMinutes = max(0, travelDurationMinutes) + max(0, bufferMinutes)
        return nextArrival.addingTimeInterval(TimeInterval(-totalMinutes * 60))
    }

    func segmentBetween(stops: [TripStop], from stop: TripStop) -> (next: TripStop, departure: Date)? {
        let ordered = stops.sorted { $0.sortIndex < $1.sortIndex }
        guard let index = ordered.firstIndex(where: { $0.id == stop.id }),
              ordered.indices.contains(index + 1) else {
            return nil
        }
        let next = ordered[index + 1]
        return (next, stop.plannedDeparture)
    }

    func recalculateFromArrival(
        _ arrival: Date,
        at startIndex: Int,
        stops: [TripStop],
        segments: [TravelSegment]
    ) {
        guard stops.indices.contains(startIndex) else { return }

        let resolvedArrival = stops[startIndex].isTimeAnchor ? stops[startIndex].plannedArrival : arrival
        stops[startIndex].plannedArrival = resolvedArrival
        stops[startIndex].plannedDeparture = plannedDeparture(
            arrival: resolvedArrival,
            visitDurationMinutes: stops[startIndex].plannedVisitDurationMinutes
        )

        guard startIndex + 1 < stops.count else { return }
        for index in (startIndex + 1)..<stops.count {
            let previous = stops[index - 1]
            let stop = stops[index]
            let segment = segments.first { $0.toStopID == stop.id }
            let travelMinutes = resolvedTravelMinutes(segment: segment, from: previous, to: stop)
            let bufferMinutes = max(0, segment?.bufferMinutes ?? 0)
            let calculatedArrival = previous.plannedDeparture.addingTimeInterval(TimeInterval((travelMinutes + bufferMinutes) * 60))
            let nextArrival = stop.isTimeAnchor ? stop.plannedArrival : calculatedArrival
            stop.plannedArrival = nextArrival
            stop.plannedDeparture = plannedDeparture(
                arrival: nextArrival,
                visitDurationMinutes: stop.plannedVisitDurationMinutes
            )
            segment?.plannedDeparture = previous.plannedDeparture
        }
    }

    func recalculateTrip(_ trip: TripPlan, anchor: Date? = nil) {
        let stops = trip.sortedStops
        guard let first = stops.first else { return }
        recalculateFromArrival(
            anchor ?? first.plannedArrival,
            at: 0,
            stops: stops,
            segments: trip.sortedTravelSegments
        )
        trip.updatedAt = .now
    }

    func reconnectAndRecalculate(_ trip: TripPlan) {
        let stops = trip.sortedStops
        let segments = trip.sortedTravelSegments
        guard let first = stops.first else { return }

        let requiredSegmentCount = max(0, stops.count - 1)
        for index in segments.indices {
            segments[index].sortIndex = index
            if index < requiredSegmentCount {
                segments[index].fromStopID = stops[index].id
                segments[index].toStopID = stops[index + 1].id
            } else {
                // A deleted stop can leave an unused segment in SwiftData. Disconnect
                // it so it cannot be selected accidentally during later recalculations.
                segments[index].fromStopID = nil
                segments[index].toStopID = nil
            }
        }
        recalculateTrip(trip, anchor: first.plannedArrival)
    }

    func recalculateAfterDeparture(
        _ departure: Date,
        from completedIndex: Int,
        stops: [TripStop],
        segments: [TravelSegment]
    ) {
        guard stops.indices.contains(completedIndex) else { return }
        stops[completedIndex].plannedDeparture = departure
        let nextIndex = completedIndex + 1
        guard stops.indices.contains(nextIndex) else { return }

        let next = stops[nextIndex]
        let segment = segments.first { $0.toStopID == next.id }
        let travelMinutes = resolvedTravelMinutes(segment: segment, from: stops[completedIndex], to: next)
        let bufferMinutes = max(0, segment?.bufferMinutes ?? 0)
        let arrival = departure.addingTimeInterval(TimeInterval((travelMinutes + bufferMinutes) * 60))
        recalculateFromArrival(arrival, at: nextIndex, stops: stops, segments: segments)
    }

    private func inferredTravelMinutes(from: TripStop, to: TripStop) -> Int {
        max(0, Int(to.plannedArrival.timeIntervalSince(from.plannedDeparture) / 60))
    }

    private func resolvedTravelMinutes(segment: TravelSegment?, from: TripStop, to: TripStop) -> Int {
        if let storedMinutes = segment?.plannedDurationMinutes, storedMinutes > 0 {
            return storedMinutes
        }
        return inferredTravelMinutes(from: from, to: to)
    }
}
