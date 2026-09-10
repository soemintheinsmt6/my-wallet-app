import Foundation
import SwiftData
import WalletDomain

@Model
final class BudgetRecord {
    var id: UUID = UUID()
    var payload: Data?

    init(_ value: Budget) throws {
        id = value.id
        payload = try JSONEncoder().encode(value)
    }

    var value: Budget {
        get throws {
            guard let payload else { throw PlanningError.missingItem }
            return try JSONDecoder().decode(Budget.self, from: payload)
        }
    }

    func apply(_ value: Budget) throws { payload = try JSONEncoder().encode(value) }
}
