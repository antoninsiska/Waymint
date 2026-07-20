import Foundation
import SwiftData

@MainActor
enum PlaceBankImporter {
    static func importExistingStops(from cities: [CityPlan], modelContext: ModelContext) {
        for city in cities {
            PlaceBankDeduplicator.consolidate(in: city, modelContext: modelContext)
            var knownPlaces = city.sortedBankPlaces
            for stop in city.sortedTripPlans.flatMap(\.sortedStops) where stop.stopType != .transfer {
                guard !knownPlaces.contains(where: {
                    PlaceBankDeduplicator.matches(
                        title: stop.title,
                        address: stop.address,
                        latitude: stop.latitude,
                        longitude: stop.longitude,
                        place: $0
                    )
                }) else { continue }

                let place = PlaceBankItem(
                    title: stop.title,
                    stopType: stop.stopType,
                    highlights: stop.sortedChecklistItems.map(\.title).filter { !$0.isEmpty }.joined(separator: "\n"),
                    mainReason: stop.mainReason,
                    note: stop.note,
                    recommendedVisitDurationMinutes: stop.plannedVisitDurationMinutes,
                    address: stop.address,
                    latitude: stop.latitude,
                    longitude: stop.longitude
                )
                place.city = city
                city.addBankPlace(place)
                modelContext.insert(place)
                knownPlaces.append(place)
            }
        }
    }
}
