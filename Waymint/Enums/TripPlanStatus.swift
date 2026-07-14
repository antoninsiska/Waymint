import Foundation

enum TripPlanStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case planned
    case active
    case completed
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Rozpracovany"
        case .planned: "Naplanovany"
        case .active: "Aktivni"
        case .completed: "Dokonceny"
        case .archived: "Archiv"
        }
    }
}

