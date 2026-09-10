import Foundation
import SwiftData
import WalletDomain

@Model
final class RecurringSeriesRecord {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var payload: Data?

    init(_ value: RecurringSeries) throws {
        id = value.id
        payload = try JSONEncoder().encode(value)
    }

    var value: RecurringSeries {
        get throws {
            guard let payload else { throw PlanningError.missingItem }
            return try JSONDecoder().decode(RecurringSeries.self, from: payload)
        }
    }

    func apply(_ value: RecurringSeries) throws { payload = try JSONEncoder().encode(value) }
}
