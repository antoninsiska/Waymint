import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityService: ObservableObject {
    @Published private(set) var activityID: String?
    @Published var errorMessage: String?
    @Published private(set) var statusMessage = WaymintLocalization.text("Live Activity zatím není spuštěná.")

    func refreshStatus() {
        if let activity = Activity<WaymintTripActivityAttributes>.activities.first {
            activityID = activity.id
            errorMessage = nil
            statusMessage = WaymintLocalization.text("Live Activity běží. Dej aplikaci na pozadí nebo zamkni zařízení.")
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activityID = nil
            statusMessage = WaymintLocalization.text("Live Activities jsou povolené. Spusť je tlačítkem níže.")
        } else {
            activityID = nil
            statusMessage = WaymintLocalization.text("Live Activities nejsou na zařízení povolené.")
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
            errorMessage = WaymintLocalization.text("Live Activities nejsou na zařízení povolené.")
            statusMessage = WaymintLocalization.text("Zapni Live Activities v nastavení systému.")
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
            statusMessage = WaymintLocalization.text("Live Activity je spuštěná. Dej aplikaci na pozadí nebo zamkni zařízení.")
        } catch {
            errorMessage = WaymintLocalization.format("Live Activity se nepodařilo spustit: %@", error.localizedDescription)
            statusMessage = WaymintLocalization.text("Požadavek ActivityKit selhal.")
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
        statusMessage = WaymintLocalization.text("Live Activity byla ukončena.")
    }

    private var currentActivity: Activity<WaymintTripActivityAttributes>? {
        if let activityID,
           let matching = Activity<WaymintTripActivityAttributes>.activities.first(where: { $0.id == activityID }) {
            return matching
        }
        return Activity<WaymintTripActivityAttributes>.activities.first
    }

    private func liveActivityStaleDate(for stop: TripStop) -> Date {
        max(stop.plannedDeparture.addingTimeInterval(60 * 60), Date().addingTimeInterval(8 * 60 * 60))
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
            phaseTitle: WaymintLocalization.text(isAtPlace ? "Na místě" : "Dojezd"),
            languageCode: liveActivityLanguageCode,
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

    private var liveActivityLanguageCode: String {
        let selected = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "waymintAppLanguage") ?? "system") ?? .system
        if selected != .system { return selected.rawValue }
        return Locale.current.language.languageCode?.identifier ?? "cs"
    }
}
