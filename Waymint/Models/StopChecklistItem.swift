import Foundation
import SwiftData

@Model
final class StopChecklistItem {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    var stop: TripStop?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
