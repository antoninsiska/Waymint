import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityService: ObservableObject {
    @Published private(set) var activityID: String?
    @Published var errorMessage: String?
    @Published private(set) var statusMessage = "Live Activity zatim neni spustena."

    func refreshStatus() {
        if let activity = Activity<WaymintTripActivityAttributes>.activities.first {
            activityID = activity.id
            errorMessage = nil
            statusMessage = "Live Activity bezi. Dej appku na pozadi nebo zamkni zarizeni."
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activityID = nil
            statusMessage = "Live Activities jsou povolene. Spust je tlacitkem nize."
        } else {
            activityID = nil
            statusMessage = "Live Activities nejsou na zarizeni povolene."
        }
    }

    func start(
        trip: TripPlan,
        currentStop: TripStop,
        nextStop: TripStop?,
        showCurrentStop: Bool,
        showNextStop: Bool,
        showDepartureTime: Bool,
        showDelay: Bool
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "Live Activities nejsou na zarizeni povolene."
            statusMessage = "Zapni Live Activities v nastaveni systemu."
            return
        }

        for activity in Activity<WaymintTripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = WaymintTripActivityAttributes(tripID: trip.id, tripTitle: trip.title)
        let state = contentState(
            currentStop: currentStop,
            nextStop: nextStop,
            showCurrentStop: showCurrentStop,
            showNextStop: showNextStop,
            showDepartureTime: showDepartureTime,
            showDelay: showDelay
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: state,
                    staleDate: liveActivityStaleDate(for: currentStop),
                    relevanceScore: 100
                ),
                pushType: nil
            )
            activityID = activity.id
            errorMessage = nil
            statusMessage = "Live Activity spustena. Dej appku na pozadi nebo zamkni zarizeni."
        } catch {
            errorMessage = "Live Activity se nepodarilo spustit: \(error.localizedDescription)"
            statusMessage = "ActivityKit request selhal."
        }
    }

    func update(
        currentStop: TripStop,
        nextStop: TripStop?,
        showCurrentStop: Bool,
        showNextStop: Bool,
        showDepartureTime: Bool,
        showDelay: Bool
    ) async {
        guard let activity = currentActivity else { return }
        let state = contentState(
            currentStop: currentStop,
            nextStop: nextStop,
            showCurrentStop: showCurrentStop,
            showNextStop: showNextStop,
            showDepartureTime: showDepartureTime,
            showDelay: showDelay
        )
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: liveActivityStaleDate(for: currentStop),
                relevanceScore: 100
            )
        )
    }

    func end() async {
        guard let activity = currentActivity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activityID = nil
        statusMessage = "Live Activity ukoncena."
    }

    private var currentActivity: Activity<WaymintTripActivityAttributes>? {
        Activity<WaymintTripActivityAttributes>.activities.first { $0.id == activityID }
    }

    private func liveActivityStaleDate(for stop: TripStop) -> Date {
        max(stop.plannedDeparture.addingTimeInterval(30 * 60), Date().addingTimeInterval(2 * 60 * 60))
    }

    private func contentState(
        currentStop: TripStop,
        nextStop: TripStop?,
        showCurrentStop: Bool,
        showNextStop: Bool,
        showDepartureTime: Bool,
        showDelay: Bool
    ) -> WaymintTripActivityAttributes.ContentState {
        let now = Date()
        let isAtPlace = currentStop.status == .active || currentStop.status == .completed
        let targetDate = isAtPlace ? currentStop.plannedDeparture : currentStop.plannedArrival
        let delayReferenceDate = isAtPlace ? currentStop.plannedDeparture : currentStop.plannedArrival
        let delayMinutes = Int(now.timeIntervalSince(delayReferenceDate) / 60)
        return WaymintTripActivityAttributes.ContentState(
            currentStopName: currentStop.title,
            nextStopName: nextStop?.title,
            phaseTitle: isAtPlace ? "Na místě" : "Dojezd",
            remainingMinutes: max(0, Int(ceil(targetDate.timeIntervalSince(now) / 60))),
            targetDate: targetDate,
            plannedDeparture: currentStop.plannedDeparture,
            delayMinutes: delayMinutes,
            showCurrentStop: showCurrentStop,
            showNextStop: showNextStop,
            showDepartureTime: showDepartureTime,
            showDelay: showDelay
        )
    }
}
