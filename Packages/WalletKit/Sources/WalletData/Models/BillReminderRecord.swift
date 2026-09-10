import Foundation
import SwiftData
import WalletDomain

@Model
final class BillReminderRecord {
    var id: UUID = UUID()
    var payload: Data?

    init(_ value: BillReminder) throws {
        id = value.id
        payload = try JSONEncoder().encode(value)
    }

    var value: BillReminder {
        get throws {
            guard let payload else { throw PlanningError.missingItem }
            return try JSONDecoder().decode(BillReminder.self, from: payload)
        }
    }

    func apply(_ value: BillReminder) throws { payload = try JSONEncoder().encode(value) }
}
