import Foundation
import SwiftData

@Model
final class AttachmentItem {
    var id: UUID = UUID()
    var title: String = ""
    var localFilePath: String = ""
    var mimeType: String = ""
    var createdAt: Date = Date()

    var stop: TripStop?

    init(
        id: UUID = UUID(),
        title: String,
        localFilePath: String,
        mimeType: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.localFilePath = localFilePath
        self.mimeType = mimeType
        self.createdAt = createdAt
    }
}
