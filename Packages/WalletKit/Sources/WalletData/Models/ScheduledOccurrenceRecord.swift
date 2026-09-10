import Foundation
import SwiftData
import WalletDomain

@Model
final class ScheduledOccurrenceRecord {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var payload: Data?

    init(_ value: ScheduledOccurrence) throws {
        id = value.id
        payload = try JSONEncoder().encode(value)
    }

    var value: ScheduledOccurrence {
        get throws {
            guard let payload else { throw PlanningError.missingItem }
            return try JSONDecoder().decode(ScheduledOccurrence.self, from: payload)
        }
    }

    func apply(_ value: ScheduledOccurrence) throws { payload = try JSONEncoder().encode(value) }
}
