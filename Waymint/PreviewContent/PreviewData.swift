import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static func container() -> ModelContainer {
        do {
            let container = try WaymintModelContainer.make(inMemory: true)
            seed(into: container.mainContext)
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }

    static func seed(into context: ModelContext) {
        let city = CityPlan(name: "Helsinky", country: "Finsko")

        let morning = TripPlan(title: "Centrum Helsinek", date: .now, startTime: .now, status: .planned)
        let afternoon = TripPlan(title: "Muzea a kavarny", date: .now.addingTimeInterval(86_400), startTime: .now, status: .draft, sortIndex: 1)

        city.addTripPlan(morning)
        city.addTripPlan(afternoon)

        let hotel = TripStop(
            title: "Hotel u nadrazi",
            stopType: .hotel,
            plannedArrival: date(hour: 8, minute: 30),
            plannedDeparture: date(hour: 9, minute: 0),
            plannedVisitDurationMinutes: 30,
            address: "Kaivokatu 1, Helsinki",
            latitude: 60.1719,
            longitude: 24.9414,
            mainReason: "Start dne bez zbytecneho zdrzeni",
            sortIndex: 0
        )

        let museum = TripStop(
            title: "Ateneum",
            stopType: .museum,
            plannedArrival: date(hour: 9, minute: 15),
            plannedDeparture: date(hour: 11, minute: 0),
            plannedVisitDurationMinutes: 105,
            address: "Kaivokatu 2, Helsinki",
            latitude: 60.1702,
            longitude: 24.9441,
            note: "Zacit hlavni sbirkou, pak kratka pauza.",
            mainReason: "Klasicka finska malba",
            sortIndex: 1
        )

        let cafe = TripStop(
            title: "Cafe Engel",
            stopType: .cafe,
            plannedArrival: date(hour: 11, minute: 20),
            plannedDeparture: date(hour: 12, minute: 0),
            plannedVisitDurationMinutes: 40,
            address: "Aleksanterinkatu 26, Helsinki",
            latitude: 60.1696,
            longitude: 24.9522,
            mainReason: "Rychla pauza pred pristavem",
            isRequired: false,
            sortIndex: 2
        )

        let restaurant = TripStop(
            title: "Old Market Hall",
            stopType: .restaurant,
            plannedArrival: date(hour: 12, minute: 20),
            plannedDeparture: date(hour: 13, minute: 15),
            plannedVisitDurationMinutes: 55,
            address: "Etelaranta, Helsinki",
            latitude: 60.1676,
            longitude: 24.9532,
            mainReason: "Obed u pristavu",
            sortIndex: 3
        )

        museum.addChecklistItem(StopChecklistItem(title: "Hlavni vystava", sortIndex: 0))
        museum.addChecklistItem(StopChecklistItem(title: "Vybrany obraz od Edelfelta", sortIndex: 1))
        museum.addChecklistItem(StopChecklistItem(title: "Historicka hala", sortIndex: 2))

        let ticket = TicketItem(
            title: "Ateneum vstupenka",
            ticketType: .pdf,
            localFilePath: "Preview/Tickets/ateneum.pdf",
            note: "Ukazkova metadata bez realneho souboru"
        )
        museum.addTicket(ticket)
        morning.addTicket(ticket)

        [hotel, museum, cafe, restaurant].forEach { morning.addStop($0) }
        [
            TravelSegment(transportMode: .walking, plannedDurationMinutes: 12, fromStopID: hotel.id, toStopID: museum.id, sortIndex: 0),
            TravelSegment(transportMode: .publicTransport, plannedDurationMinutes: 14, fromStopID: museum.id, toStopID: cafe.id, sortIndex: 1),
            TravelSegment(transportMode: .walking, plannedDurationMinutes: 10, fromStopID: cafe.id, toStopID: restaurant.id, sortIndex: 2)
        ].forEach { morning.addTravelSegment($0) }

        context.insert(city)
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }
}
