import Foundation

enum AppRoute: Hashable {
    case city(UUID)
    case trip(UUID)
    case stop(UUID)
    case activeTrip(UUID)
}

