import XCTest
@testable import Waymint

@MainActor
final class ScheduleCalculatorTests: XCTestCase {
    private let calculator = ScheduleCalculator()

    func testRecalculateTripMovesWholeTimelineFromNewStart() {
        let trip = makeTrip()
        let anchor = Date(timeIntervalSince1970: 2_000_000)
        calculator.recalculateTrip(trip, anchor: anchor)

        XCTAssertEqual(trip.sortedStops[0].plannedArrival, anchor)
        XCTAssertEqual(trip.sortedStops[0].plannedDeparture, anchor.addingTimeInterval(30 * 60))
        XCTAssertEqual(trip.sortedStops[1].plannedArrival, anchor.addingTimeInterval(45 * 60))
    }

    func testVisitDurationAndTravelDurationPropagateForward() {
        let trip = makeTrip()
        let stops = trip.sortedStops
        stops[0].plannedVisitDurationMinutes = 60
        trip.sortedTravelSegments[0].plannedDurationMinutes = 25
        calculator.recalculateTrip(trip, anchor: stops[0].plannedArrival)

        XCTAssertEqual(stops[1].plannedArrival, stops[0].plannedArrival.addingTimeInterval(85 * 60))
    }

    func testReconnectAfterMoveUsesNewStopOrder() {
        let trip = makeTrip()
        let stops = trip.sortedStops
        stops[0].sortIndex = 1
        stops[1].sortIndex = 0
        calculator.reconnectAndRecalculate(trip)

        let segment = trip.sortedTravelSegments[0]
        XCTAssertEqual(segment.fromStopID, trip.sortedStops[0].id)
        XCTAssertEqual(segment.toStopID, trip.sortedStops[1].id)
    }

    func testFlexibleTripCanBeAnchoredAtCurrentTime() {
        let trip = makeTrip()
        trip.hasFixedStartTime = false
        let now = Date()
        calculator.recalculateTrip(trip, anchor: now)
        XCTAssertEqual(trip.sortedStops[0].plannedArrival.timeIntervalSince(now), 0, accuracy: 0.01)
    }

    func testDelayAfterDepartureMovesFollowingStop() {
        let trip = makeTrip()
        let delayedDeparture = trip.sortedStops[0].plannedDeparture.addingTimeInterval(20 * 60)

        calculator.recalculateAfterDeparture(
            delayedDeparture,
            from: 0,
            stops: trip.sortedStops,
            segments: trip.sortedTravelSegments
        )

        XCTAssertEqual(
            trip.sortedStops[1].plannedArrival,
            delayedDeparture.addingTimeInterval(15 * 60)
        )
    }

    func testDeletingStopReconnectsRemainingTimeline() {
        let trip = makeThreeStopTrip()
        let removedID = trip.sortedStops[1].id
        trip.stops?.removeAll { $0.id == removedID }

        calculator.reconnectAndRecalculate(trip)

        XCTAssertEqual(trip.sortedStops.count, 2)
        XCTAssertEqual(trip.sortedTravelSegments[0].fromStopID, trip.sortedStops[0].id)
        XCTAssertEqual(trip.sortedTravelSegments[0].toStopID, trip.sortedStops[1].id)
        XCTAssertNil(trip.sortedTravelSegments[1].fromStopID)
        XCTAssertNil(trip.sortedTravelSegments[1].toStopID)
    }

    private func makeTrip() -> TripPlan {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = TripStop(
            title: "Start",
            plannedArrival: start,
            plannedDeparture: start.addingTimeInterval(30 * 60),
            plannedVisitDurationMinutes: 30,
            sortIndex: 0
        )
        let second = TripStop(
            title: "Cíl",
            plannedArrival: start.addingTimeInterval(45 * 60),
            plannedDeparture: start.addingTimeInterval(75 * 60),
            plannedVisitDurationMinutes: 30,
            sortIndex: 1
        )
        let trip = TripPlan(title: "Test", stops: [first, second])
        trip.addTravelSegment(TravelSegment(
            plannedDurationMinutes: 15,
            fromStopID: first.id,
            toStopID: second.id,
            sortIndex: 0
        ))
        return trip
    }

    private func makeThreeStopTrip() -> TripPlan {
        let trip = makeTrip()
        let second = trip.sortedStops[1]
        let third = TripStop(
            title: "Třetí",
            plannedArrival: second.plannedDeparture.addingTimeInterval(10 * 60),
            plannedDeparture: second.plannedDeparture.addingTimeInterval(40 * 60),
            plannedVisitDurationMinutes: 30,
            sortIndex: 2
        )
        trip.addStop(third)
        trip.addTravelSegment(TravelSegment(
            plannedDurationMinutes: 10,
            fromStopID: second.id,
            toStopID: third.id,
            sortIndex: 1
        ))
        return trip
    }
}
