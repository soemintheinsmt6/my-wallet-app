import SwiftUI
import WalletDomain

/// A month calendar of drinking days. Tap a day to mark it, or to change or clear it.
public struct DrinkingDaysView: View {
    @ObservedObject private var viewModel: DrinkingDaysViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: DayKey?

    public init(viewModel: DrinkingDaysViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            Section {
                DrinkingCalendar(viewModel: viewModel) { editing = $0 }
            } header: {
                monthHeader
            }

            Section {
                let summary = viewModel.summary
                HStack(spacing: WalletMetrics.medium) {
                    WalletStatTile(title: "Drinking", value: daysText(summary.drinkingDays),
                                   symbol: "wineglass", tint: DrinkingDaysView.tint)
                    WalletStatTile(title: "Alcohol-free", value: daysText(summary.alcoholFreeDays),
                                   symbol: "leaf", tint: .green)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                HStack(spacing: WalletMetrics.medium) {
                    WalletStatTile(title: "Drinks", value: "\(summary.totalDrinks)",
                                   symbol: "number", tint: DrinkingDaysView.tint)
                    WalletStatTile(title: "Since last drink", value: summary.daysSinceLastDrink.map(daysText) ?? "—",
                                   symbol: "calendar", tint: .blue)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Monthly counts include only days up to today. Days you don't mark count as alcohol-free.")
            }

            let marked = markedDaysInMonth
            if !marked.isEmpty {
                Section("This Month") {
                    ForEach(marked) { day in
                        Button { editing = day.day } label: { DrinkingDayRow(day: day, calendar: viewModel.calendar) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit drinking day")
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Clear", role: .destructive) { unmark(day.day) }
                            }
                    }
                }
            }
        }
        .navigationTitle("Drinking Days")
        .toolbar {
            ToolbarItem {
                Button { editing = viewModel.today } label: { Label("Mark Today", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { day in
            DrinkingDayEditorView(viewModel: viewModel, day: day, existing: viewModel.days[day])
        }
        .alert("Unable to Update Drinking Days", isPresented: Binding(
            get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") { Task { await viewModel.reload() } }
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.observe() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.reload() } }
        }
    }

    static let tint = Color.orange

    private var monthHeader: some View {
        HStack {
            Button { viewModel.showMonth(offset: -1) } label: {
                Image(systemName: "chevron.left").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Button { viewModel.showCurrentMonth() } label: {
                Text(viewModel.month.date(in: viewModel.calendar), format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .accessibilityHint("Shows the current month")
            Spacer()
            Button { viewModel.showMonth(offset: 1) } label: {
                Image(systemName: "chevron.right").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .disabled(!viewModel.canShowNextMonth)
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
        .textCase(nil)
    }

    private var markedDaysInMonth: [DrinkingDay] {
        viewModel.days.values
            .filter { $0.day.year == viewModel.month.year && $0.day.month == viewModel.month.month }
            .sorted { $0.day > $1.day }
    }

    private func daysText(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    private func unmark(_ day: DayKey) {
        Task {
            do { try await viewModel.unmark(day) }
            catch { viewModel.errorMessage = error.localizedDescription }
        }
    }
}

private struct DrinkingCalendar: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let select: (DayKey) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: WalletMetrics.tight), count: 7)

    var body: some View {
        let calendar = viewModel.calendar
        let today = viewModel.today
        LazyVGrid(columns: columns, spacing: WalletMetrics.tight) {
            ForEach(Array(weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            ForEach(0..<leadingBlanks(calendar), id: \.self) { _ in Color.clear.frame(height: 1) }
            ForEach(monthDays(calendar)) { day in
                let entry = viewModel.days[day]
                let isFuture = day > today
                Button { select(day) } label: {
                    DayCell(day: day.day, isMarked: entry != nil, isToday: day == today, isFuture: isFuture)
                }
                .buttonStyle(.plain)
                .disabled(isFuture || viewModel.isSaving)
                .accessibilityLabel(Text(day.date(in: calendar), format: .dateTime.weekday(.wide).month(.wide).day()))
                .accessibilityValue(entry == nil ? "Alcohol-free" : "Drinking day")
                .accessibilityAddTraits(entry != nil ? .isSelected : [])
            }
        }
        .padding(.vertical, WalletMetrics.small)
    }

    /// Short weekday names starting from the calendar's first weekday.
    private func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func leadingBlanks(_ calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: viewModel.month.date(in: calendar))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func monthDays(_ calendar: Calendar) -> [DayKey] {
        let month = viewModel.month
        let count = calendar.range(of: .day, in: .month, for: month.date(in: calendar))?.count ?? 0
        return (1...max(count, 1)).map { DayKey(year: month.year, month: month.month, day: $0) }
    }
}

private struct DayCell: View {
    let day: Int
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
                    .fill(isMarked ? DrinkingDaysView.tint : Color.clear)
                    .overlay { if isToday && !isMarked { Circle().strokeBorder(DrinkingDaysView.tint, lineWidth: 1.5) } }
                    .frame(width: 36, height: 36)
            }
            .contentShape(.rect)
    }
}

private struct DrinkingDayRow: View {
    let day: DrinkingDay
    let calendar: Calendar

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: "wineglass", color: DrinkingDaysView.tint)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(day.day.date(in: calendar), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if !day.note.isEmpty {
                    Text(day.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: WalletMetrics.small)
            if let drinks = day.drinks {
                Text(drinks == 1 ? "1 drink" : "\(drinks) drinks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            WalletDisclosure()
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.hair)
        .contentShape(Rectangle())
    }
}
