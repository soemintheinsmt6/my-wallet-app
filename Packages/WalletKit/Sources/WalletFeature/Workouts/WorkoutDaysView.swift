import SwiftUI
import WalletDomain

/// Workout days as a month calendar or a year chart. Tap a day to mark it, or to change or clear it.
public struct WorkoutDaysView: View {
    enum Scope: String, CaseIterable {
        case month = "Month"
        case year = "Year"
    }

    @ObservedObject private var viewModel: WorkoutDaysViewModel
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("workoutDays.scope") private var scope = Scope.month
    @State private var editing: DayKey?

    public init(viewModel: WorkoutDaysViewModel) { self.viewModel = viewModel }

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
        .navigationTitle("Workout Days")
        .toolbar {
            ToolbarItem {
                Button { editing = viewModel.today } label: { Label("Mark Today", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { day in
            WorkoutDayEditorView(viewModel: viewModel, day: day, existing: viewModel.days[day])
        }
        .alert("Unable to Update Workout Days", isPresented: Binding(
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

    /// Vivid, and apart from the income green and the drinking orange.
    static let tint = Color.pink

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
                           accessibilityLabel: "Workout days chart",
                           accessibilityValue: "\(heatmap.workoutDays) workout days, \(heatmap.restDays) rest days",
                           describe: describe) { editing = $0 }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } footer: {
            WalletListFooter("Darker squares mean longer workouts. Days marked without a time use the lightest shade.")
        }

        Section {
            DayStatRow(WalletStatTile(title: "Workouts", value: dayCountText(heatmap.workoutDays),
                                      symbol: "figure.run", tint: Self.tint),
                       WalletStatTile(title: "Rest", value: dayCountText(heatmap.restDays),
                                      symbol: "bed.double", tint: .indigo))
            DayStatRow(WalletStatTile(title: "Time", value: workoutDurationText(minutes: heatmap.totalMinutes),
                                      symbol: "clock", tint: Self.tint),
                       WalletStatTile(title: "Longest streak", value: dayCountText(heatmap.longestStreak),
                                      symbol: "flame", tint: .orange))
        }
    }

    private var yearTitle: String {
        switch viewModel.heatmapPeriod {
        case .pastYear: "Past Year"
        case .year(let year): String(year)
        }
    }

    private func describe(_ cell: WorkoutHeatmap.Cell) -> String {
        let date = cell.day.date(in: viewModel.calendar).formatted(.dateTime.month(.abbreviated).day().year())
        guard cell.level > 0 else { return "\(date): rest day" }
        let parts = [cell.activity?.title, cell.minutes.map { workoutDurationText(minutes: $0) }].compactMap { $0 }
        return "\(date): \(parts.isEmpty ? "workout" : parts.joined(separator: ", "))"
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
                             markedValue: "Workout day", unmarkedValue: "Rest day",
                             select: { editing = $0 })
                // Otherwise the line follows the first weekday letter, inset from every other line.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }

        Section {
            let summary = viewModel.summary
            DayStatRow(WalletStatTile(title: "Workouts", value: dayCountText(summary.workoutDays),
                                      symbol: "figure.run", tint: Self.tint),
                       WalletStatTile(title: "Rest", value: dayCountText(summary.restDays),
                                      symbol: "bed.double", tint: .indigo))
            DayStatRow(WalletStatTile(title: "Time", value: workoutDurationText(minutes: summary.totalMinutes),
                                      symbol: "clock", tint: Self.tint),
                       WalletStatTile(title: "Current streak", value: dayCountText(summary.currentStreak),
                                      symbol: "flame", tint: .orange))
        } footer: {
            WalletListFooter("Monthly counts include only days up to today. Days you don't mark count as rest days. "
                             + "The streak counts workout days in a row up to today.")
        }

        let marked = markedDaysInMonth
        if !marked.isEmpty {
            Section("This Month") {
                ForEach(marked) { day in
                    Button { editing = day.day } label: { WorkoutDayRow(day: day, calendar: viewModel.calendar) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit workout day")
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) { unmark(day.day) }
                        }
                }
            }
        }
    }

    private var markedDaysInMonth: [WorkoutDay] {
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

private struct WorkoutDayRow: View {
    let day: WorkoutDay
    let calendar: Calendar

    /// The activity, then the exercises, so a row reads "Gym · Chest, Push-up, Crunch".
    private var subtitle: String? {
        let exercises = day.exercises.isEmpty ? nil : day.exercises.joined(separator: ", ")
        let parts = [day.activity?.title, exercises].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: day.symbol, color: WorkoutDaysView.tint)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(day.day.date(in: calendar), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !day.note.isEmpty {
                    Text(day.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: WalletMetrics.small)
            if let minutes = day.minutes {
                Text(workoutDurationText(minutes: minutes))
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
