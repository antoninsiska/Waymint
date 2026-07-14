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
}

