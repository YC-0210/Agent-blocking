import Foundation
import SwiftData

@Model
class MotivationPhoto {
    @Attribute(.unique) var id: String
    // Cropped, downscaled image shown on the main screen. Stored as an external
    // file by SwiftData so the SQLite store stays small.
    @Attribute(.externalStorage) var imageData: Data
    // Downscaled source photo kept so the crop can be re-framed later. Nil for
    // photos added before this was introduced (v2.2.0).
    @Attribute(.externalStorage) var originalImageData: Data?
    var caption: String
    var sortOrder: Int
    var createdAt: Date

    init(
        imageData: Data,
        originalImageData: Data? = nil,
        caption: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID().uuidString
        self.imageData = imageData
        self.originalImageData = originalImageData
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
