import Foundation
import SwiftData

@Model
final class PlaceBankItem {
    var id: UUID = UUID()
    var title: String = ""
    var stopTypeRawValue: String = StopType.custom.rawValue
    var highlights: String = ""
    var mainReason: String = ""
    var note: String = ""
    var recommendedVisitDurationMinutes: Int = 45
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var city: CityPlan?

    init(
        title: String,
        stopType: StopType = .custom,
        highlights: String = "",
        mainReason: String = "",
        note: String = "",
        recommendedVisitDurationMinutes: Int = 45,
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.title = title
        self.stopTypeRawValue = stopType.rawValue
        self.highlights = highlights
        self.mainReason = mainReason
        self.note = note
        self.recommendedVisitDurationMinutes = recommendedVisitDurationMinutes
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var stopType: StopType {
        get { StopType(rawValue: stopTypeRawValue) ?? .custom }
        set { stopTypeRawValue = newValue.rawValue }
    }
}
