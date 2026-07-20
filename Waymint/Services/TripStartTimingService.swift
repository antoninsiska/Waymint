import Foundation

struct TripStartTimingService {
    private let calendar = Calendar.current
    private let allowedDifference: TimeInterval = 15 * 60

    func needsConfirmation(for trip: TripPlan, now: Date = .now) -> Bool {
        guard trip.status != .active, trip.status != .paused else { return false }
        guard calendar.isDate(trip.date, inSameDayAs: now) else { return true }
        guard trip.hasFixedStartTime else { return false }
        return abs(plannedStart(for: trip).timeIntervalSince(now)) > allowedDifference
    }

    func plannedStart(for trip: TripPlan) -> Date {
        trip.sortedStops.first?.plannedArrival ?? trip.startTime
    }

    func movePlanToNow(_ trip: TripPlan, now: Date = .now) {
        trip.date = now
        trip.startTime = now
        if !trip.sortedStops.isEmpty {
            ScheduleCalculator().recalculateTrip(trip, anchor: now)
        }
        trip.updatedAt = now
    }
}
