import CryptoKit
import Foundation

public enum RecurrenceFrequency: String, CaseIterable, Codable, Sendable {
    case daily, weekly, biweekly, monthly, yearly
}

public struct RecurrenceRule: Codable, Equatable, Sendable {
    public var frequency: RecurrenceFrequency
    public var endDate: Date?
    public var count: Int?
    public var timeZoneIdentifier: String

    public init(frequency: RecurrenceFrequency = .monthly, endDate: Date? = nil, count: Int? = nil,
                timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.frequency = frequency
        self.endDate = endDate
        self.count = count
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func validate(start: Date) throws {
        guard start.timeIntervalSince1970.isFinite, TimeZone(identifier: timeZoneIdentifier) != nil,
              count.map({ (1...100_000).contains($0) }) ?? true,
              endDate.map({ $0.timeIntervalSince1970.isFinite && $0 >= start }) ?? true else {
            throw PlanningError.invalidSchedule
        }
    }

    /// Each date is anchored to the original date, avoiding month-end and leap-year drift.
    public func date(start: Date, index: Int) -> Date? {
        guard index >= 0, index < 100_000, count.map({ index < $0 }) ?? true else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        let component: Calendar.Component
        let offset: Int
        switch frequency {
        case .daily: component = .day; offset = index
        case .weekly: component = .day; offset = index * 7
        case .biweekly: component = .day; offset = index * 14
        case .monthly: component = .month; offset = index
        case .yearly: component = .year; offset = index
        }
        guard let date = calendar.date(byAdding: component, value: offset, to: start),
              endDate.map({ date <= $0 }) ?? true else { return nil }
        return date
    }
}

public enum SeriesState: String, Codable, CaseIterable, Sendable { case active, paused, cancelled }

public struct RecurringSeries: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var template: RecordDraft
    public var rule: RecurrenceRule
    public var startDate: Date
    public var nextIndex: Int
    public var state: SeriesState

    public init(id: UUID, template: RecordDraft, rule: RecurrenceRule, nextIndex: Int = 1, state: SeriesState = .active) {
        self.id = id
        self.template = template
        self.template.recurrence = nil
        self.rule = rule
        startDate = template.date
        self.nextIndex = nextIndex
        self.state = state
    }

    public var nextDate: Date? { rule.date(start: startDate, index: nextIndex) }
}

public struct ScheduledOccurrence: Identifiable, Codable, Sendable, Equatable {
    public let seriesID: UUID
    public let index: Int
    public var skipped: Bool
    public var completed: Bool
    public var overrideDraft: RecordDraft?
    public var id: UUID { Self.identifier(owner: seriesID, index: index, kind: "recurring") }

    public init(seriesID: UUID, index: Int, skipped: Bool = false, completed: Bool = false, overrideDraft: RecordDraft? = nil) {
        self.seriesID = seriesID
        self.index = index
        self.skipped = skipped
        self.completed = completed
        self.overrideDraft = overrideDraft
    }

    public static func identifier(owner: UUID, index: Int, kind: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data("\(kind):\(owner.uuidString):\(index)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

public enum PlanningError: LocalizedError {
    case invalidSchedule, invalidBudget, invalidName, missingItem, busy, invalidReminder, completedOccurrence
    public var errorDescription: String? {
        switch self {
        case .invalidSchedule: "Choose a valid schedule, end date and occurrence count (1–100,000)."
        case .invalidBudget: "Choose a positive budget, valid currency and period of at least one day."
        case .invalidName: "Enter a name with 1–80 characters."
        case .missingItem: "This item or one of its linked accounts or categories is no longer available."
        case .busy: "Another change is being saved. Please try again."
        case .invalidReminder: "Choose a valid bill amount, currency, due date and reminder offset."
        case .completedOccurrence: "This occurrence has already been processed. Edit its saved record instead."
        }
    }
}

@MainActor
public protocol RecurringRepository: AnyObject {
    func fetchRecurringSeries() async throws -> [RecurringSeries]
    func fetchOccurrences() async throws -> [ScheduledOccurrence]
    func updateRecurringSeries(_ series: RecurringSeries) async throws
    func saveOccurrence(_ occurrence: ScheduledOccurrence) async throws
    func generateDueRecords(through date: Date) async throws -> Int
    func changes() -> AsyncStream<Void>
}
