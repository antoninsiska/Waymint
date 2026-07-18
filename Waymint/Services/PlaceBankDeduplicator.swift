import CoreLocation
import SwiftData

@MainActor
enum PlaceBankDeduplicator {
    static func matches(
        title: String,
        address: String,
        latitude: Double?,
        longitude: Double?,
        place: PlaceBankItem
    ) -> Bool {
        let incomingAddress = normalized(address)
        if !incomingAddress.isEmpty, incomingAddress == normalized(place.address) { return true }

        var isNearby = false
        if let latitude, let longitude,
           let placeLatitude = place.latitude, let placeLongitude = place.longitude {
            let distance = CLLocation(latitude: latitude, longitude: longitude)
                .distance(from: CLLocation(latitude: placeLatitude, longitude: placeLongitude))
            isNearby = distance <= 60
            if isNearby { return true }
        }

        let incomingTitle = normalized(title)
        let sameTitle = !incomingTitle.isEmpty && incomingTitle == normalized(place.title)
        let neitherHasLocation = latitude == nil && longitude == nil && place.latitude == nil && place.longitude == nil
        let neitherHasAddress = incomingAddress.isEmpty && normalized(place.address).isEmpty
        return sameTitle && neitherHasLocation && neitherHasAddress
    }

    static func consolidate(in city: CityPlan, modelContext: ModelContext) {
        var unique: [PlaceBankItem] = []
        for place in city.sortedBankPlaces {
            if let existing = unique.first(where: {
                matches(
                    title: place.title,
                    address: place.address,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    place: $0
                )
            }) {
                merge(place, into: existing)
                modelContext.delete(place)
            } else {
                unique.append(place)
            }
        }
    }

    private static func merge(_ duplicate: PlaceBankItem, into target: PlaceBankItem) {
        if target.address.isEmpty { target.address = duplicate.address }
        target.mainReason = mergedText(target.mainReason, duplicate.mainReason)
        target.note = mergedText(target.note, duplicate.note)
        if target.latitude == nil { target.latitude = duplicate.latitude }
        if target.longitude == nil { target.longitude = duplicate.longitude }
        target.recommendedVisitDurationMinutes = max(target.recommendedVisitDurationMinutes, duplicate.recommendedVisitDurationMinutes)

        let points = (target.highlights + "\n" + duplicate.highlights)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        target.highlights = points.filter { seen.insert(normalized($0)).inserted }.joined(separator: "\n")
        target.updatedAt = .now
    }

    private static func mergedText(_ first: String, _ second: String) -> String {
        let first = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return second }
        guard !second.isEmpty, normalized(first) != normalized(second) else { return first }
        return first + "\n\n" + second
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
