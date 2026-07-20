import Foundation

enum StopStatus: String, CaseIterable, Identifiable, Codable {
    case planned
    case next
    case active
    case completed
    case skipped
    case delayed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .planned: "Plánovaná"
        case .next: "Následující"
        case .active: "Probíhá"
        case .completed: "Dokončená"
        case .skipped: "Přeskočená"
        case .delayed: "Zpožděná"
        }
    }
}
