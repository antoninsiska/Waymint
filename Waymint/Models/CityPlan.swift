import Foundation
import SwiftData

@Model
final class CityPlan {
    var id: UUID = UUID()
    var name: String = ""
    var country: String = ""
    var landingTitle: String = ""
    var landingSubtitle: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TripPlan.city)
    var tripPlans: [TripPlan]?

    init(
        id: UUID = UUID(),
        name: String,
        country: String = "",
        landingTitle: String = "",
        landingSubtitle: String = "",
        sortIndex: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tripPlans: [TripPlan] = []
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.landingTitle = landingTitle
        self.landingSubtitle = landingSubtitle
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tripPlans = tripPlans
    }

    var sortedTripPlans: [TripPlan] {
        (tripPlans ?? []).sorted { lhs, rhs in
            if lhs.sortIndex == rhs.sortIndex {
                return lhs.date < rhs.date
            }
            return lhs.sortIndex < rhs.sortIndex
        }
    }

    var tripPlanCount: Int {
        tripPlans?.count ?? 0
    }

    func addTripPlan(_ trip: TripPlan) {
        if tripPlans == nil {
            tripPlans = []
        }
        tripPlans?.append(trip)
    }
}
