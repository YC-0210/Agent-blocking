import Foundation
import SwiftData

@Model
class NFCTapEvent {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var action: String
    var profileId: UUID
    var profileName: String

    init(
        action: String,
        profileId: UUID,
        profileName: String
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.action = action
        self.profileId = profileId
        self.profileName = profileName
    }

    static let actionStartBlock = "start_block"
    static let actionEndBlock = "end_block"
    static let actionForceStart = "force_start"

    static func tapEvents(
        since date: Date,
        in context: ModelContext
    ) -> [NFCTapEvent] {
        let descriptor = FetchDescriptor<NFCTapEvent>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func tapCount(
        since date: Date,
        in context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<NFCTapEvent>(
            predicate: #Predicate { $0.timestamp >= date }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
