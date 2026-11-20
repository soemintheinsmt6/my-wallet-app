import SwiftUI
import WalletDomain

/// A month of tappable days, marked days filled with the tracker's tint. Shared by Drinking Days
/// and Workout Days; future days are shown but cannot be marked.
struct DayMonthCalendar: View {
    /// The first day of the month shown.
    let month: DayKey
    let today: DayKey
    let calendar: Calendar
    let tint: Color
    let isDisabled: Bool
    let isMarked: (DayKey) -> Bool
    /// Read by VoiceOver after each day's date, e.g. "Drinking day" or "Alcohol-free".
    let markedValue: String
    let unmarkedValue: String
    let select: (DayKey) -> Void

    /// A plain grid, not a lazy one: a lazy grid inside a list row misjudges its height as the row is
    /// reused, which made the list jump while scrolling. A month is at most 42 cells.
    var body: some View {
        Grid(horizontalSpacing: WalletMetrics.tight, verticalSpacing: WalletMetrics.tight) {
            GridRow {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = week[column] {
                            dayButton(day)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, WalletMetrics.small)
    }

    private func dayButton(_ day: DayKey) -> some View {
        let marked = isMarked(day)
        let isFuture = day > today
        return Button { select(day) } label: {
            DayCell(day: day.day, tint: tint, isMarked: marked, isToday: day == today, isFuture: isFuture)
        }
        .buttonStyle(.plain)
        .disabled(isFuture || isDisabled)
        .accessibilityLabel(Text(day.date(in: calendar), format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(marked ? markedValue : unmarkedValue)
        .accessibilityAddTraits(marked ? .isSelected : [])
    }

    /// The month's days in rows of seven, padded with `nil` before the first and after the last.
    private var weeks: [[DayKey?]] {
        var cells: [DayKey?] = Array(repeating: nil, count: leadingBlanks) + monthDays
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Short weekday names starting from the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: month.date(in: calendar))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var monthDays: [DayKey] {
        let count = calendar.range(of: .day, in: .month, for: month.date(in: calendar))?.count ?? 0
        return (1...max(count, 1)).map { DayKey(year: month.year, month: month.month, day: $0) }
    }
}

private struct DayCell: View {
    let day: Int
    let tint: Color
    let isMarked: Bool
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        Text("\(day)")
            .font(.callout.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(isMarked ? Color.white : (isFuture ? Color.secondary.opacity(0.5) : Color.primary))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                Circle()
                    .fill(isMarked ? tint : Color.clear)
                    .overlay { if isToday && !isMarked { Circle().strokeBorder(tint, lineWidth: 1.5) } }
                    .frame(width: 36, height: 36)
            }
            .contentShape(.rect)
    }
}
