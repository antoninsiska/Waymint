import Foundation
import SwiftData

@Model
final class TripPlan {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var startTime: Date = Date()
    var hasFixedStartTime: Bool = true
    var hasTemporaryActiveStartTime: Bool = false
    var actualStartedAt: Date?
    var actualEndedAt: Date?
    var statusRawValue: String = TripPlanStatus.draft.rawValue
    var sortIndex: Int = 0
    var landingTitle: String = ""
    var landingSubtitle: String = ""
    var photoAlbumLocalIdentifier: String?
    var photoAlbumTitle: String?
    var note: String = ""
    var scheduleChangeHistoryText: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var city: CityPlan?

    @Relationship(deleteRule: .cascade, inverse: \TripStop.tripPlan)
    var stops: [TripStop]?

    @Relationship(deleteRule: .cascade, inverse: \TravelSegment.tripPlan)
    var travelSegments: [TravelSegment]?

    @Relationship(deleteRule: .cascade, inverse: \TicketItem.tripPlan)
    var tickets: [TicketItem]?

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = .now,
        startTime: Date = .now,
        hasFixedStartTime: Bool = true,
        hasTemporaryActiveStartTime: Bool = false,
        actualStartedAt: Date? = nil,
        actualEndedAt: Date? = nil,
        status: TripPlanStatus = .draft,
        sortIndex: Int = 0,
        landingTitle: String = "",
        landingSubtitle: String = "",
        photoAlbumLocalIdentifier: String? = nil,
        photoAlbumTitle: String? = nil,
        note: String = "",
        scheduleChangeHistoryText: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        stops: [TripStop] = [],
        travelSegments: [TravelSegment] = [],
        tickets: [TicketItem] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.startTime = startTime
        self.hasFixedStartTime = hasFixedStartTime
        self.hasTemporaryActiveStartTime = hasTemporaryActiveStartTime
        self.actualStartedAt = actualStartedAt
        self.actualEndedAt = actualEndedAt
        self.statusRawValue = status.rawValue
        self.sortIndex = sortIndex
        self.landingTitle = landingTitle
        self.landingSubtitle = landingSubtitle
        self.photoAlbumLocalIdentifier = photoAlbumLocalIdentifier
        self.photoAlbumTitle = photoAlbumTitle
        self.note = note
        self.scheduleChangeHistoryText = scheduleChangeHistoryText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stops = stops
        self.travelSegments = travelSegments
        self.tickets = tickets
    }

    var status: TripPlanStatus {
        get { TripPlanStatus(rawValue: statusRawValue) ?? .draft }
        set { statusRawValue = newValue.rawValue }
    }

    var sortedStops: [TripStop] {
        (stops ?? []).sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.plannedArrival < rhs.plannedArrival
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    var sortedTickets: [TicketItem] {
        (tickets ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var sortedTravelSegments: [TravelSegment] {
        (travelSegments ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var stopCount: Int {
        stops?.count ?? 0
    }

    var ticketCount: Int {
        tickets?.count ?? 0
    }

    func addStop(_ stop: TripStop) {
        if stops == nil {
            stops = []
        }
        stops?.append(stop)
    }

    func addTravelSegment(_ segment: TravelSegment) {
        if travelSegments == nil {
            travelSegments = []
        }
        travelSegments?.append(segment)
    }

    func addTicket(_ ticket: TicketItem) {
        if tickets == nil {
            tickets = []
        }
        tickets?.append(ticket)
    }

    var timeRangeLabel: String {
        guard hasFixedStartTime else {
            return flexibleDurationLabel
        }
        guard let first = sortedStops.first, let last = sortedStops.last else {
            return startTime.waymintTime
        }
        return "\(first.plannedArrival.waymintTime)-\(last.plannedDeparture.waymintTime)"
    }

    var scheduleLabel: String {
        hasFixedStartTime ? timeRangeLabel : flexibleDurationLabel
    }

    var approximateDurationMinutes: Int {
        guard let first = sortedStops.first, let last = sortedStops.last else {
            return 0
        }
        return max(0, Int(last.plannedDeparture.timeIntervalSince(first.plannedArrival) / 60))
    }

    var actualDurationMinutes: Int? {
        guard let actualStartedAt else { return nil }
        let end = actualEndedAt ?? Date()
        return max(0, Int(end.timeIntervalSince(actualStartedAt) / 60))
    }

    private var flexibleDurationLabel: String {
        guard let actualDurationMinutes else {
            return "Bez pevného začátku"
        }
        if status == .completed {
            return "Trvalo \(actualDurationMinutes.minutesLabel)"
        }
        return "Běží \(actualDurationMinutes.minutesLabel)"
    }
}
