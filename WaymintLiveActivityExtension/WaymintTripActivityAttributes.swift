import ActivityKit
import Foundation

struct WaymintTripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var currentStopName: String
        var nextStopName: String?
        var phaseTitle: String
        var languageCode: String
        var remainingMinutes: Int
        var targetDate: Date
        var plannedDeparture: Date?
        var delayMinutes: Int
        var showCurrentStop: Bool
        var showNextStop: Bool
        var showDepartureTime: Bool
        var showDelay: Bool
    }

    var tripID: UUID
    var tripTitle: String
}
