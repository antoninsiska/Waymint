import Foundation

enum TripPlanStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case planned
    case active
    case paused
    case stopped
    case completed
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Rozpracovaný"
        case .planned: "Naplánovaný"
        case .active: "Aktivní"
        case .paused: "Pozastavená"
        case .stopped: "Zastavená"
        case .completed: "Dokončený"
        case .archived: "Archiv"
        }
    }
}
