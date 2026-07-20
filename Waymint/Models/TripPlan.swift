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
    var pausedAt: Date?
    var accumulatedPauseSeconds: Double = 0
    var offlinePreparedAt: Date?
    var delayResponseStrategyRawValue: String = DelayResponseStrategy.shiftEverything.rawValue
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
        pausedAt: Date? = nil,
        accumulatedPauseSeconds: Double = 0,
        offlinePreparedAt: Date? = nil,
        delayResponseStrategy: DelayResponseStrategy = .shiftEverything,
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
        self.pausedAt = pausedAt
        self.accumulatedPauseSeconds = accumulatedPauseSeconds
        self.offlinePreparedAt = offlinePreparedAt
        self.delayResponseStrategyRawValue = delayResponseStrategy.rawValue
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

    var delayResponseStrategy: DelayResponseStrategy {
        get { DelayResponseStrategy(rawValue: delayResponseStrategyRawValue) ?? .shiftEverything }
        set { delayResponseStrategyRawValue = newValue.rawValue }
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

    var allTickets: [TicketItem] {
        var seen = Set<UUID>()
        return (sortedTickets + sortedStops.flatMap(\.sortedTickets))
            .filter(\.isUsableTicket)
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.stop?.sortIndex ?? -1
                let rhsIndex = rhs.stop?.sortIndex ?? -1
                return lhsIndex == rhsIndex ? lhs.createdAt < rhs.createdAt : lhsIndex < rhsIndex
            }
    }

    var sortedTravelSegments: [TravelSegment] {
        (travelSegments ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var stopCount: Int {
        stops?.count ?? 0
    }

    var ticketCount: Int {
        sortedTickets.filter(\.isUsableTicket).count
    }

    var totalTicketCount: Int {
        allTickets.count
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
        let measured = max(0, Int(end.timeIntervalSince(actualStartedAt) / 60))
        let expected = expectedContentDurationMinutes

        // A trip can remain restored in the background after the user has
        // effectively finished it. Do not present that idle time as a real
        // multi-day trip duration. The underlying timestamps stay untouched
        // and remain available in the diagnostic export.
        let plausibleMaximum = max(12 * 60, expected + max(180, expected / 2))
        if (status == .completed || status == .stopped), measured > plausibleMaximum, expected > 0 {
            return expected
        }
        return measured
    }

    var hasSuspiciousRunningDuration: Bool {
        guard status == .active || status == .paused,
              let actualStartedAt else { return false }
        let measured = Int(Date().timeIntervalSince(actualStartedAt) / 60)
        return measured > max(18 * 60, expectedContentDurationMinutes * 3)
    }

    /// A conservative fallback used when old/restored activity timestamps or
    /// travel segments contain an implausible multi-day interval.
    var expectedContentDurationMinutes: Int {
        let visitMinutes = sortedStops.reduce(0) { partial, stop in
            partial + min(max(0, stop.plannedVisitDurationMinutes), 12 * 60)
        }
        let travelMinutes = sortedTravelSegments.reduce(0) { partial, segment in
            let duration = segment.plannedDurationMinutes
            return partial + ((1...(12 * 60)).contains(duration) ? duration : 0) + min(max(0, segment.bufferMinutes), 180)
        }
        return visitMinutes + travelMinutes
    }

    private var flexibleDurationLabel: String {
        guard let actualDurationMinutes else {
            return WaymintLocalization.text("Bez pevného začátku")
        }
        if hasSuspiciousRunningDuration {
            return WaymintLocalization.text("Čas vyžaduje kontrolu")
        }
        if status == .completed {
            return WaymintLocalization.format("Trvalo %@", actualDurationMinutes.minutesLabel)
        }
        if status == .stopped {
            return WaymintLocalization.format("Zastavena po %@", actualDurationMinutes.minutesLabel)
        }
        return WaymintLocalization.format("Běží %@", actualDurationMinutes.minutesLabel)
    }
}

enum DelayResponseStrategy: String, CaseIterable, Identifiable, Codable {
    case shiftEverything
    case shortenOptionalStops
    case preserveReservations
    case suggestSkipping

    var id: String { rawValue }
    var title: String {
        switch self {
        case .shiftEverything: "Posunout celý plán"
        case .shortenOptionalStops: "Zkrátit volitelné zastávky"
        case .preserveReservations: "Zachovat pevné rezervace"
        case .suggestSkipping: "Navrhovat přeskočení"
        }
    }
}
