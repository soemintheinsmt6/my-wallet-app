import Foundation

/// Figures for one calendar month, counting only days up to today, plus the current run.
public struct WorkoutSummary: Equatable, Sendable {
    public let workoutDays: Int
    public let restDays: Int
    /// Sum of the days that recorded a duration; days marked without one add nothing.
    public let totalMinutes: Int
    /// Consecutive workout days ending today, whichever month is shown. An unmarked today does not
    /// break the run, since the day is not over yet; it counts once marked.
    public let currentStreak: Int

    public init(days: [WorkoutDay], month: DayKey, today: DayKey, calendar: Calendar = .current) {
        let inMonth = days.filter { $0.day.isInMonth(of: month) && $0.day <= today }
        workoutDays = inMonth.count
        totalMinutes = inMonth.reduce(0) { $0 + ($1.minutes ?? 0) }
        restDays = max(0, DayKey.elapsedDays(in: month, today: today, calendar: calendar) - inMonth.count)

        let marked = Set(days.map(\.day))
        var day = marked.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var streak = 0
        while marked.contains(day) {
            streak += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        currentStreak = streak
    }
}
