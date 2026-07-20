import Foundation
import SwiftData

@Model
final class TicketItem {
    var id: UUID = UUID()
    var title: String = ""
    var ticketTypeRawValue: String = TicketType.textCode.rawValue
    var code: String?
    var localFilePath: String?
    var externalURLString: String?
    var createdAt: Date = Date()
    var note: String = ""

    var tripPlan: TripPlan?
    var stop: TripStop?

    init(
        id: UUID = UUID(),
        title: String,
        ticketType: TicketType = .textCode,
        code: String? = nil,
        localFilePath: String? = nil,
        externalURLString: String? = nil,
        createdAt: Date = .now,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.ticketTypeRawValue = ticketType.rawValue
        self.code = code
        self.localFilePath = localFilePath
        self.externalURLString = externalURLString
        self.createdAt = createdAt
        self.note = note
    }

    var ticketType: TicketType {
        get { TicketType(rawValue: ticketTypeRawValue) ?? .textCode }
        set { ticketTypeRawValue = newValue.rawValue }
    }

    var isUsableTicket: Bool {
        switch ticketType {
        case .textCode:
            return !(code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .link:
            let value = externalURLString ?? code
            return !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .pdf, .image, .qrCode, .barcode:
            return !(localFilePath?.isEmpty ?? true)
        }
    }
}
