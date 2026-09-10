import Foundation

/// A target the user is saving toward.
///
/// Contributions are tracked separately rather than read from an account balance, because an
/// account usually holds more than one goal's worth of money and spending from it should not
/// silently undo progress.
public struct SavingsGoal: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var targetAmount: Decimal
    public var currencyCode: String
    public var deadline: Date?
    /// Optional: the account the money is expected to sit in.
    public var accountID: UUID?
    public var note: String
    public var createdAt: Date
    public var colorValue: UInt32?

    public init(id: UUID = UUID(), name: String = "", targetAmount: Decimal = 0,
                currencyCode: String = "USD", deadline: Date? = nil, accountID: UUID? = nil,
                note: String = "", createdAt: Date = Date(), colorValue: UInt32? = nil) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.currencyCode = currencyCode
        self.deadline = deadline
        self.accountID = accountID
        self.note = note
        self.createdAt = createdAt
        self.colorValue = colorValue
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80 else { throw GoalError.invalidName }
        try RecordDraft.validateAmount(targetAmount)
        guard note.count <= 2000 else { throw GoalError.noteTooLong }
        guard Locale.commonISOCurrencyCodes.contains(currencyCode) else { throw GoalError.invalidCurrency }
        if let deadline { guard deadline.timeIntervalSince1970.isFinite else { throw GoalError.invalidDeadline } }
    }
}

/// Money put toward a goal. Negative amounts are withdrawals, so progress can go down.
public struct GoalContribution: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var goalID: UUID
    public var amount: Decimal
    public var date: Date
    public var recordID: UUID?

    public init(id: UUID = UUID(), goalID: UUID, amount: Decimal, date: Date = Date(),
                recordID: UUID? = nil) {
        self.id = id
        self.goalID = goalID
        self.amount = amount
        self.date = date
        self.recordID = recordID
    }
}

public enum GoalError: LocalizedError, Equatable {
    case invalidName
    case invalidCurrency
    case invalidDeadline
    case noteTooLong
    case invalidContribution
    case busy

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a name of up to 80 characters."
        case .invalidCurrency: "Choose a supported currency."
        case .invalidDeadline: "Choose a valid deadline."
        case .noteTooLong: "Use up to 2,000 characters for the note."
        case .invalidContribution: "Enter an amount other than zero."
        case .busy: "A goal is being saved. Please try again."
        }
    }
}

/// A goal and everything contributed toward it.
public struct GoalProgress: Identifiable, Sendable, Equatable {
    public let goal: SavingsGoal
    public let contributions: [GoalContribution]

    public var id: UUID { goal.id }
    /// Can exceed the target when the user oversaves, and can fall if they withdraw.
    public var saved: Decimal { contributions.reduce(0) { $0 + $1.amount } }
    public var remaining: Decimal { max(0, goal.targetAmount - saved) }
    public var isAchieved: Bool { goal.targetAmount > 0 && saved >= goal.targetAmount }

    public var fraction: Double {
        guard goal.targetAmount > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: saved / goal.targetAmount).doubleValue
        return min(1, max(0, value))
    }

    public init(goal: SavingsGoal, contributions: [GoalContribution]) {
        self.goal = goal
        self.contributions = contributions.sorted { $0.date < $1.date }
    }

    /// Average saved per day since the first contribution, or `nil` when there is nothing to
    /// extrapolate from.
    public func dailyRate(now: Date = Date()) -> Decimal? {
        guard let first = contributions.first, saved > 0 else { return nil }
        let elapsed = now.timeIntervalSince(first.date)
        // A single contribution today gives no rate; one day is the shortest usable window.
        let days = max(1, elapsed / 86400)
        guard days >= 1 else { return nil }
        return saved / Decimal(days)
    }

    /// When the goal would be reached at the current rate.
    ///
    /// `nil` when already achieved, when nothing has been contributed, or when the rate is so slow
    /// the answer would be meaningless rather than useful.
    public func projectedCompletion(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard !isAchieved, remaining > 0, let rate = dailyRate(now: now), rate > 0 else { return nil }
        let days = NSDecimalNumber(decimal: remaining / rate).doubleValue
        guard days.isFinite, days >= 0, days <= 365 * 20 else { return nil }
        return calendar.date(byAdding: .day, value: Int(days.rounded(.up)), to: now)
    }

    /// True when the projection lands after the deadline the user set.
    public func isBehindSchedule(now: Date = Date()) -> Bool {
        guard let deadline = goal.deadline, !isAchieved else { return false }
        guard let projected = projectedCompletion(now: now) else {
            // No contributions at all and a deadline in the past is behind by any reading.
            return deadline < now
        }
        return projected > deadline
    }
}

@MainActor
public protocol GoalRepository: AnyObject {
    func fetchGoals() async throws -> [SavingsGoal]
    func fetchGoalContributions() async throws -> [GoalContribution]
    func saveGoal(_ goal: SavingsGoal) async throws
    func deleteGoal(id: UUID) async throws
    func saveGoalContribution(_ contribution: GoalContribution) async throws
    func deleteGoalContribution(id: UUID) async throws
}

@MainActor
public struct GoalUseCases {
    private let repository: any GoalRepository

    public init(repository: any GoalRepository) { self.repository = repository }

    public func load() async throws -> [GoalProgress] {
        let goals = try await repository.fetchGoals()
        let contributions = try await repository.fetchGoalContributions()
        return Self.progress(goals: goals, contributions: contributions)
    }

    public func save(_ goal: SavingsGoal) async throws {
        var value = goal
        value.name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = goal.note.trimmingCharacters(in: .whitespacesAndNewlines)
        try value.validate()
        try await repository.saveGoal(value)
    }

    public func delete(id: UUID) async throws { try await repository.deleteGoal(id: id) }

    public func contribute(to goal: SavingsGoal, amount: Decimal, recordID: UUID? = nil,
                           date: Date = Date()) async throws {
        guard amount != 0 else { throw GoalError.invalidContribution }
        try await repository.saveGoalContribution(
            GoalContribution(goalID: goal.id, amount: amount, date: date, recordID: recordID))
    }

    public func deleteContribution(id: UUID) async throws {
        try await repository.deleteGoalContribution(id: id)
    }

    /// Pure, so it needs no actor: callers off the main actor (and tests) can use it directly.
    public nonisolated static func progress(goals: [SavingsGoal],
                                            contributions: [GoalContribution]) -> [GoalProgress] {
        let byGoal = Dictionary(grouping: contributions, by: \.goalID)
        return goals
            .map { GoalProgress(goal: $0, contributions: byGoal[$0.id] ?? []) }
            .sorted { first, second in
                // Unfinished goals first, then soonest deadline, then newest.
                if first.isAchieved != second.isAchieved { return !first.isAchieved }
                switch (first.goal.deadline, second.goal.deadline) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return first.goal.createdAt > second.goal.createdAt
                }
            }
    }
}
