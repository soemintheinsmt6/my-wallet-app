import SwiftUI
import WalletDomain

/// Drinking days as a month calendar or a year chart. Tap a day to mark it, or to change or clear it.
public struct DrinkingDaysView: View {
    enum Scope: String, CaseIterable {
        case month = "Month"
        case year = "Year"
    }

    @ObservedObject private var viewModel: DrinkingDaysViewModel
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("drinkingDays.scope") private var scope = Scope.month
    @State private var editing: DayKey?

    public init(viewModel: DrinkingDaysViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            Picker("View", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Inset to the same margins as the rows below, rather than touching the screen edges.
            .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                      bottom: WalletMetrics.small, trailing: WalletMetrics.large))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            switch scope {
            case .month: monthSections
            case .year: yearSections
            }
        }
        .listStyle(.plain)
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

    @ViewBuilder private var yearSections: some View {
        let heatmap = viewModel.heatmap
        // As in month view, the title is a row so it sits close under the switch.
        Section {
            DayTrackerPager(previousLabel: "Previous year", nextLabel: "Next year",
                            canShowPrevious: viewModel.canShowEarlierYear, canShowNext: viewModel.canShowLaterYear,
                            showPrevious: { viewModel.showYear(offset: -1) },
                            showNext: { viewModel.showYear(offset: 1) },
                            title: {
                Text(yearTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
            })
            .listRowSeparator(.hidden)
            DayHeatmapView(weeks: heatmap.weeks, monthLabels: heatmap.monthLabels, first: heatmap.first,
                           today: viewModel.today, calendar: viewModel.calendar, tint: Self.tint,
                           isDisabled: viewModel.isSaving,
                           accessibilityLabel: "Drinking days chart",
                           accessibilityValue: "\(heatmap.drinkingDays) drinking days, \(heatmap.alcoholFreeDays) alcohol-free days",
                           describe: describe) { editing = $0 }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } footer: {
            WalletListFooter("Darker squares mean more drinks. Days marked without a count use the lightest shade.")
        }

        Section {
            DayStatRow(WalletStatTile(title: "Drinking", value: dayCountText(heatmap.drinkingDays),
                                      symbol: "wineglass", tint: Self.tint),
                       WalletStatTile(title: "Alcohol-free", value: dayCountText(heatmap.alcoholFreeDays),
                                      symbol: "leaf", tint: .green))
            DayStatRow(WalletStatTile(title: "Drinks", value: "\(heatmap.totalDrinks)",
                                      symbol: "number", tint: Self.tint),
                       WalletStatTile(title: "Longest alcohol-free", value: dayCountText(heatmap.longestAlcoholFreeStreak),
                                      symbol: "flame", tint: .blue))
        }
    }

    private var yearTitle: String {
        switch viewModel.heatmapPeriod {
        case .pastYear: "Past Year"
        case .year(let year): String(year)
        }
    }

    private func describe(_ cell: DrinkingHeatmap.Cell) -> String {
        let date = cell.day.date(in: viewModel.calendar).formatted(.dateTime.month(.abbreviated).day().year())
        guard cell.level > 0 else { return "\(date): alcohol-free" }
        guard let drinks = cell.drinks else { return "\(date): drinking day" }
        return "\(date): \(drinks == 1 ? "1 drink" : "\(drinks) drinks")"
    }

    @ViewBuilder private var monthSections: some View {
        // The month title is a row, not a section header: a flat list pads headers with a tall gap
        // that pushed the calendar away from the Month/Year switch.
        Section {
            DayTrackerPager(previousLabel: "Previous month", nextLabel: "Next month",
                            canShowNext: viewModel.canShowNextMonth,
                            showPrevious: { viewModel.showMonth(offset: -1) },
                            showNext: { viewModel.showMonth(offset: 1) },
                            title: {
                Button { viewModel.showCurrentMonth() } label: {
                    Text(viewModel.month.date(in: viewModel.calendar), format: .dateTime.month(.wide).year())
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .accessibilityHint("Shows the current month")
            })
            .listRowSeparator(.hidden)
            DayMonthCalendar(month: viewModel.month, today: viewModel.today, calendar: viewModel.calendar,
                             tint: Self.tint, isDisabled: viewModel.isSaving,
                             isMarked: { viewModel.days[$0] != nil },
                             markedValue: "Drinking day", unmarkedValue: "Alcohol-free",
                             select: { editing = $0 })
                // Otherwise the line follows the first weekday letter, inset from every other line.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }

        Section {
            let summary = viewModel.summary
            DayStatRow(WalletStatTile(title: "Drinking", value: dayCountText(summary.drinkingDays),
                                      symbol: "wineglass", tint: Self.tint),
                       WalletStatTile(title: "Alcohol-free", value: dayCountText(summary.alcoholFreeDays),
                                      symbol: "leaf", tint: .green))
            DayStatRow(WalletStatTile(title: "Drinks", value: "\(summary.totalDrinks)",
                                      symbol: "number", tint: Self.tint),
                       WalletStatTile(title: "Since last drink", value: summary.daysSinceLastDrink.map(dayCountText) ?? "—",
                                      symbol: "calendar", tint: .blue))
        } footer: {
            WalletListFooter("Monthly counts include only days up to today. Days you don't mark count as alcohol-free.")
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

    private var markedDaysInMonth: [DrinkingDay] {
        viewModel.days.values
            .filter { $0.day.isInMonth(of: viewModel.month) }
            .sorted { $0.day > $1.day }
    }

    private func unmark(_ day: DayKey) {
        Task {
            do { try await viewModel.unmark(day) }
            catch { viewModel.errorMessage = error.localizedDescription }
        }
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
        .walletListRowPadding(WalletMetrics.hair)
        .contentShape(Rectangle())
    }
}
