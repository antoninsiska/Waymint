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
        case .planned: "Planovana"
        case .next: "Nasledujici"
        case .active: "Probiha"
        case .completed: "Dokoncena"
        case .skipped: "Preskocena"
        case .delayed: "Zpozdena"
        }
    }
}

