import Foundation
import SwiftData

@Model
final class TravelSegment {
    var id: UUID = UUID()
    var transportModeRawValue: String = TransportMode.walking.rawValue
    var plannedDurationMinutes: Int = 0
    var plannedDeparture: Date?
    var bufferMinutes: Int = 0
    var fromStopID: UUID?
    var toStopID: UUID?
    var note: String = ""
    var sortIndex: Int = 0

    var tripPlan: TripPlan?

    init(
        id: UUID = UUID(),
        transportMode: TransportMode = .walking,
        plannedDurationMinutes: Int = 0,
        plannedDeparture: Date? = nil,
        bufferMinutes: Int = 0,
        fromStopID: UUID? = nil,
        toStopID: UUID? = nil,
        note: String = "",
        sortIndex: Int = 0
    ) {
        self.id = id
        self.transportModeRawValue = transportMode.rawValue
        self.plannedDurationMinutes = (fromStopID != nil || toStopID != nil)
            ? max(1, plannedDurationMinutes)
            : max(0, plannedDurationMinutes)
        self.plannedDeparture = plannedDeparture
        self.bufferMinutes = bufferMinutes
        self.fromStopID = fromStopID
        self.toStopID = toStopID
        self.note = note
        self.sortIndex = sortIndex
    }

    var transportMode: TransportMode {
        get { TransportMode(rawValue: transportModeRawValue) ?? .walking }
        set { transportModeRawValue = newValue.rawValue }
    }
}
