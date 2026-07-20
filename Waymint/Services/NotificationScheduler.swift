import CoreLocation
import Foundation
import UserNotifications

struct NotificationScheduleResult: Sendable {
    let scheduledCount: Int
    let failedCount: Int
    let authorizationStatus: UNAuthorizationStatus

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }
}

struct NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func requestPermissionIfNeeded() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func pendingCount(for tripID: UUID? = nil) async -> Int {
        let requests = await center.pendingNotificationRequests()
        guard let tripID else { return requests.count }
        return requests.filter { $0.identifier.hasPrefix(tripID.uuidString) }.count
    }

    func cancelNotifications(for tripID: UUID) {
        let prefix = tripID.uuidString
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
            self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    @discardableResult
    func scheduleTripNotifications(for trip: TripPlan) async -> NotificationScheduleResult {
        let authorized = (try? await requestPermissionIfNeeded()) == true
        let status = await authorizationStatus()
        guard authorized else {
            saveDiagnostic(count: 0, failed: 0, message: "authorization:\(status.rawValue)")
            return NotificationScheduleResult(scheduledCount: 0, failedCount: 0, authorizationStatus: status)
        }

        cancelNotifications(for: trip.id)

        var scheduled = 0
        var failed = 0
        let eligibleStops = trip.sortedStops
            .filter { $0.status == .planned || $0.status == .next || $0.status == .active }
            .prefix(18)

        for stop in eligibleStops {
            if let next = nextStop(after: stop, in: trip), stop.plannedDeparture > Date().addingTimeInterval(30) {
                let reminderDate = max(Date().addingTimeInterval(30), stop.plannedDeparture.addingTimeInterval(-5 * 60))
                let added = await addTimeNotification(
                    identifier: "\(trip.id.uuidString)-leave-\(stop.id.uuidString)",
                    title: WaymintLocalization.text("Brzy je čas vyrazit"),
                    body: departureReminderBody(from: stop, next: next),
                    date: reminderDate,
                    tripID: trip.id,
                    stopID: next.id
                )
                added ? (scheduled += 1) : (failed += 1)
            }

            if stop.plannedArrival > Date().addingTimeInterval(30), stop.status != .active {
                let added = await addTimeNotification(
                    identifier: "\(trip.id.uuidString)-arrive-\(stop.id.uuidString)",
                    title: WaymintLocalization.text("Další místo podle plánu"),
                    body: WaymintLocalization.format("Teď je na řadě %@.", stop.title),
                    date: stop.plannedArrival,
                    tripID: trip.id,
                    stopID: stop.id
                )
                added ? (scheduled += 1) : (failed += 1)
            }

            if stop.ticketCount > 0, await addTicketLocationNotificationIfPossible(tripID: trip.id, stop: stop) {
                scheduled += 1
            }
        }

        saveDiagnostic(count: scheduled, failed: failed, message: "scheduled")
        return NotificationScheduleResult(scheduledCount: scheduled, failedCount: failed, authorizationStatus: status)
    }

    func scheduleTestNotification() async throws {
        guard try await requestPermissionIfNeeded() else {
            throw NotificationSchedulerError.permissionDenied
        }
        let content = UNMutableNotificationContent()
        content.title = WaymintLocalization.text("Test upozornění Waymint")
        content.body = WaymintLocalization.text("Upozornění fungují správně.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(identifier: "waymint-test", content: content, trigger: trigger))
    }

    private func nextStop(after stop: TripStop, in trip: TripPlan) -> TripStop? {
        let stops = trip.sortedStops
        guard let index = stops.firstIndex(where: { $0.id == stop.id }), stops.indices.contains(index + 1) else { return nil }
        return stops[index + 1]
    }

    private func departureReminderBody(from stop: TripStop, next: TripStop) -> String {
        if let reminder = stop.sortedChecklistItems.first(where: { !$0.isDone }) {
            return WaymintLocalization.format("Za chvíli vyraz na %@. Nezapomeň: %@", next.title, reminder.title)
        }
        if next.ticketCount > 0 {
            return WaymintLocalization.format("Za chvíli vyraz na %@. Vstupenky máš uložené ve Waymintu.", next.title)
        }
        return WaymintLocalization.format("Za chvíli vyraz na %@.", next.title)
    }

    private func addTimeNotification(
        identifier: String,
        title: String,
        body: String,
        date: Date,
        tripID: UUID,
        stopID: UUID
    ) async -> Bool {
        guard date > .now else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["tripID": tripID.uuidString, "stopID": stopID.uuidString, "route": "activeTrip"]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    private func addTicketLocationNotificationIfPossible(tripID: UUID, stop: TripStop) async -> Bool {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return false }
        let content = UNMutableNotificationContent()
        content.title = WaymintLocalization.text("Vstupenky po ruce")
        content.body = WaymintLocalization.format("Jsi poblíž %@. Otevři si vstupenky k tomuhle místu.", stop.title)
        content.sound = .default
        content.userInfo = ["tripID": tripID.uuidString, "stopID": stop.id.uuidString, "route": "tickets"]

        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: 180,
            identifier: "\(tripID.uuidString)-tickets-\(stop.id.uuidString)"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        do {
            try await center.add(UNNotificationRequest(identifier: region.identifier, content: content, trigger: UNLocationNotificationTrigger(region: region, repeats: false)))
            return true
        } catch {
            return false
        }
    }

    private func saveDiagnostic(count: Int, failed: Int, message: String) {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: "waymintNotificationLastScheduleAt")
        defaults.set(count, forKey: "waymintNotificationLastScheduleCount")
        defaults.set(failed, forKey: "waymintNotificationLastFailureCount")
        defaults.set(message, forKey: "waymintNotificationLastScheduleMessage")
    }
}

enum NotificationSchedulerError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        WaymintLocalization.text("Oznámení nejsou povolená v nastavení systému.")
    }
}
