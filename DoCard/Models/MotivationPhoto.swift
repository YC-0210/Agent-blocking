import Foundation
import SwiftData

@Model
class MotivationPhoto {
    @Attribute(.unique) var id: String
    // Copied, downscaled image bytes. Stored as an external file by SwiftData
    // so the SQLite store stays small.
    @Attribute(.externalStorage) var imageData: Data
    var caption: String
    var sortOrder: Int
    var createdAt: Date

    init(
        imageData: Data,
        caption: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID().uuidString
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    static let maxCount = 5

    static func allSorted(in context: ModelContext) -> [MotivationPhoto] {
        let descriptor = FetchDescriptor<MotivationPhoto>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func count(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<MotivationPhoto>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
