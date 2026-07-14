import Foundation
import SwiftData

@Model
final class TripStop {
    var id: UUID = UUID()
    var title: String = ""
    var stopTypeRawValue: String = StopType.custom.rawValue
    var statusRawValue: String = StopStatus.planned.rawValue
    var plannedArrival: Date = Date()
    var plannedDeparture: Date = Date()
    var plannedVisitDurationMinutes: Int = 30
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var note: String = ""
    var mainReason: String = ""
    var isRequired: Bool = true
    var sortIndex: Int = 0
    var actualStart: Date?
    var actualEnd: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var tripPlan: TripPlan?

    @Relationship(deleteRule: .cascade, inverse: \StopChecklistItem.stop)
    var checklistItems: [StopChecklistItem]?

    @Relationship(deleteRule: .cascade, inverse: \TicketItem.stop)
    var tickets: [TicketItem]?

    @Relationship(deleteRule: .cascade, inverse: \AttachmentItem.stop)
    var attachments: [AttachmentItem]?

    init(
        id: UUID = UUID(),
        title: String,
        stopType: StopType = .custom,
        status: StopStatus = .planned,
        plannedArrival: Date = .now,
        plannedDeparture: Date = .now.addingTimeInterval(30 * 60),
        plannedVisitDurationMinutes: Int = 30,
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        note: String = "",
        mainReason: String = "",
        isRequired: Bool = true,
        sortIndex: Int = 0,
        actualStart: Date? = nil,
        actualEnd: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        checklistItems: [StopChecklistItem] = [],
        tickets: [TicketItem] = [],
        attachments: [AttachmentItem] = []
    ) {
        self.id = id
        self.title = title
        self.stopTypeRawValue = stopType.rawValue
        self.statusRawValue = status.rawValue
        self.plannedArrival = plannedArrival
        self.plannedDeparture = plannedDeparture
        self.plannedVisitDurationMinutes = plannedVisitDurationMinutes
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.note = note
        self.mainReason = mainReason
        self.isRequired = isRequired
        self.sortIndex = sortIndex
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checklistItems = checklistItems
        self.tickets = tickets
        self.attachments = attachments
    }

    var stopType: StopType {
        get { StopType(rawValue: stopTypeRawValue) ?? .custom }
        set { stopTypeRawValue = newValue.rawValue }
    }

    var status: StopStatus {
        get { StopStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }

    var sortedChecklistItems: [StopChecklistItem] {
        (checklistItems ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var sortedTickets: [TicketItem] {
        (tickets ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var ticketCount: Int {
        tickets?.count ?? 0
    }

    var checklistItemCount: Int {
        checklistItems?.count ?? 0
    }

    func addChecklistItem(_ item: StopChecklistItem) {
        if checklistItems == nil {
            checklistItems = []
        }
        checklistItems?.append(item)
    }

    func addTicket(_ ticket: TicketItem) {
        if tickets == nil {
            tickets = []
        }
        tickets?.append(ticket)
    }

    var coordinateIsValid: Bool {
        latitude != nil && longitude != nil
    }
}
