import Foundation
import CoreLocation
import UserNotifications

struct NotificationScheduler {
    func requestPermissionIfNeeded() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func cancelNotifications(for tripID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [tripID.uuidString])
    }

    func scheduleTripNotifications(for trip: TripPlan) {
        let center = UNUserNotificationCenter.current()
        let prefix = trip.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: trip.sortedStops.flatMap { stop in
            [
                "\(prefix)-leave-\(stop.id.uuidString)",
                "\(prefix)-arrive-\(stop.id.uuidString)",
                "\(prefix)-tickets-\(stop.id.uuidString)"
            ]
        })

        for stop in trip.sortedStops {
            scheduleTimeNotification(
                identifier: "\(prefix)-leave-\(stop.id.uuidString)",
                title: "Je čas odejít",
                body: "Vyraz na \(stop.title).",
                date: stop.plannedArrival.addingTimeInterval(-10 * 60),
                stopID: stop.id
            )

            scheduleTimeNotification(
                identifier: "\(prefix)-arrive-\(stop.id.uuidString)",
                title: "Správný čas na místo",
                body: "\(stop.title) je teď v plánu.",
                date: stop.plannedArrival,
                stopID: stop.id
            )

            scheduleTicketLocationNotificationIfPossible(tripID: trip.id, stop: stop)
        }
    }

    private func scheduleTimeNotification(identifier: String, title: String, body: String, date: Date, stopID: UUID) {
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["stopID": stopID.uuidString, "route": "tickets"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func scheduleTicketLocationNotificationIfPossible(tripID: UUID, stop: TripStop) {
        guard stop.ticketCount > 0,
              let latitude = stop.latitude,
              let longitude = stop.longitude else { return }

        let content = UNMutableNotificationContent()
        content.title = "Vstupenky po ruce"
        content.body = "Jsi poblíž \(stop.title). Otevři si vstupenky k tomuhle místu."
        content.sound = .default
        content.userInfo = ["stopID": stop.id.uuidString, "route": "tickets"]

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: 180,
            identifier: "\(tripID.uuidString)-tickets-\(stop.id.uuidString)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        let trigger = UNLocationNotificationTrigger(region: region, repeats: false)
        let request = UNNotificationRequest(identifier: region.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
