import Foundation
import SwiftData

@Model
class EmergencyUnlockEvent {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var sessionId: String
    var profileId: UUID
    var sessionDuration: TimeInterval

    init(
        sessionId: String,
        profileId: UUID,
        sessionDuration: TimeInterval
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.sessionId = sessionId
        self.profileId = profileId
        self.sessionDuration = sessionDuration
    }

    static func events(
        since date: Date,
        in context: ModelContext
    ) -> [EmergencyUnlockEvent] {
        let descriptor = FetchDescriptor<EmergencyUnlockEvent>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func count(
        since date: Date,
        in context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<EmergencyUnlockEvent>(
            predicate: #Predicate { $0.timestamp >= date }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }
}
