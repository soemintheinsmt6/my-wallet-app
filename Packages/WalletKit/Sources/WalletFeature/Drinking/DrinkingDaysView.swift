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
            yearHeader
                .listRowSeparator(.hidden)
            DrinkingHeatmapView(heatmap: heatmap, today: viewModel.today, calendar: viewModel.calendar,
                                isDisabled: viewModel.isSaving) { editing = $0 }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        } footer: {
            WalletListFooter("Darker squares mean more drinks. Days marked without a count use the lightest shade.")
        }

        Section {
            statRow(WalletStatTile(title: "Drinking", value: daysText(heatmap.drinkingDays),
                                   symbol: "wineglass", tint: DrinkingDaysView.tint),
                    WalletStatTile(title: "Alcohol-free", value: daysText(heatmap.alcoholFreeDays),
                                   symbol: "leaf", tint: .green))
            statRow(WalletStatTile(title: "Drinks", value: "\(heatmap.totalDrinks)",
                                   symbol: "number", tint: DrinkingDaysView.tint),
                    WalletStatTile(title: "Longest alcohol-free", value: daysText(heatmap.longestAlcoholFreeStreak),
                                   symbol: "flame", tint: .blue))
        }
    }

    private var yearHeader: some View {
        HStack {
            Button { viewModel.showYear(offset: -1) } label: {
                Image(systemName: "chevron.left").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .disabled(!viewModel.canShowEarlierYear)
            .accessibilityLabel("Previous year")
            Spacer()
            Text(yearTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Button { viewModel.showYear(offset: 1) } label: {
                Image(systemName: "chevron.right").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .disabled(!viewModel.canShowLaterYear)
            .accessibilityLabel("Next year")
        }
        .buttonStyle(.borderless)
        .textCase(nil)
    }

    private var yearTitle: String {
        switch viewModel.heatmapPeriod {
        case .pastYear: "Past Year"
        case .year(let year): String(year)
        }
    }

    /// Two stat tiles side by side. The row keeps a small inset so its separator can sit on the
    /// same leading edge as every other line on the screen; only the left tile is padded in, which
    /// gives Drinking and Drinks room from the edge without moving the lines.
    private func statRow(_ left: WalletStatTile, _ right: WalletStatTile) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            left.padding(.leading, WalletMetrics.medium)
            right
        }
        .listRowInsets(EdgeInsets(top: 0, leading: WalletMetrics.tight, bottom: 0, trailing: WalletMetrics.tight))
        .listRowBackground(Color.clear)
        // The row content starts at `tight`; this puts the line at the standard 16 pt margin.
        .alignmentGuide(.listRowSeparatorLeading) { _ in WalletMetrics.large - WalletMetrics.tight }
    }

    @ViewBuilder private var monthSections: some View {
        // The month title is a row, not a section header: a flat list pads headers with a tall gap
        // that pushed the calendar away from the Month/Year switch.
        Section {
            monthHeader
                .listRowSeparator(.hidden)
            DrinkingCalendar(viewModel: viewModel) { editing = $0 }
                // Otherwise the line follows the first weekday letter, inset from every other line.
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }

        Section {
            let summary = viewModel.summary
            statRow(WalletStatTile(title: "Drinking", value: daysText(summary.drinkingDays),
                                   symbol: "wineglass", tint: DrinkingDaysView.tint),
                    WalletStatTile(title: "Alcohol-free", value: daysText(summary.alcoholFreeDays),
                                   symbol: "leaf", tint: .green))
            statRow(WalletStatTile(title: "Drinks", value: "\(summary.totalDrinks)",
                                   symbol: "number", tint: DrinkingDaysView.tint),
                    WalletStatTile(title: "Since last drink", value: summary.daysSinceLastDrink.map(daysText) ?? "—",
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

/// A contribution-chart year: weeks run left to right, weekdays top to bottom, and it opens
/// scrolled to the most recent week.
private struct DrinkingHeatmapView: View {
    let heatmap: DrinkingHeatmap
    let today: DayKey
    let calendar: Calendar
    let isDisabled: Bool
    let select: (DayKey) -> Void

    @State private var hovered: DrinkingHeatmap.Cell?

    private static let cell: CGFloat = 13
    private static let gap: CGFloat = 3
    private static let pitch = cell + gap
    private static let labelHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(alignment: .top, spacing: Self.gap) {
                weekdayLabels
                // An anchor rather than `scrollTo`, which also scrolls the enclosing list and threw it
                // back to the chart whenever the row reappeared. Rebuilt per period to start at its end.
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        monthLabels
                        grid
                    }
                    .padding(.trailing, Self.gap)
                }
                .defaultScrollAnchor(.trailing)
                .id(heatmap.first)
            }
            legend
        }
        .padding(.vertical, WalletMetrics.small)
        // 365 squares are too many to step through; the month view is the accessible way to edit.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drinking days chart")
        .accessibilityValue("\(heatmap.drinkingDays) drinking days, \(heatmap.alcoholFreeDays) alcohol-free days")
        .accessibilityHint("Switch to Month to review or change individual days.")
    }

    /// Every other weekday is labelled, as GitHub does, to keep the column narrow.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Self.gap) {
            Color.clear.frame(width: 1, height: Self.labelHeight)
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 ? calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.cell)
            }
        }
    }

    private var monthLabels: some View {
        HStack(spacing: Self.gap) {
            ForEach(heatmap.weeks.indices, id: \.self) { week in
                let label = heatmap.monthLabels.first { $0.week == week }
                // Drawn at its natural width, overflowing into the following columns.
                Text(label.map { $0.month.date(in: calendar).formatted(.dateTime.month(.abbreviated)) } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Self.cell, height: Self.labelHeight, alignment: .leading)
            }
        }
    }

    /// Drawn as one canvas rather than a button per day: hundreds of views made the list stutter
    /// whenever the chart scrolled into view.
    private var grid: some View {
        Canvas { context, _ in
            for (week, column) in heatmap.weeks.enumerated() {
                for (row, cell) in column.enumerated() {
                    guard let cell else { continue }
                    let rect = CGRect(x: CGFloat(week) * Self.pitch, y: CGFloat(row) * Self.pitch,
                                      width: Self.cell, height: Self.cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3, style: .continuous),
                                 with: .color(Self.color(level: cell.level)))
                    if cell.day == today {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5, style: .continuous),
                                       with: .color(.primary), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: max(0, CGFloat(heatmap.weeks.count) * Self.pitch - Self.gap), height: 7 * Self.pitch - Self.gap)
        .contentShape(.rect)
        .gesture(SpatialTapGesture().onEnded { value in
            guard !isDisabled, let cell = cell(at: value.location) else { return }
            select(cell.day)
        })
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovered = cell(at: location)
            case .ended: hovered = nil
            }
        }
    }

    private func cell(at location: CGPoint) -> DrinkingHeatmap.Cell? {
        let week = Int(location.x / Self.pitch), row = Int(location.y / Self.pitch)
        guard location.x >= 0, location.y >= 0, heatmap.weeks.indices.contains(week), (0..<7).contains(row) else { return nil }
        return heatmap.weeks[week][row]
    }

    private var legend: some View {
        HStack(spacing: Self.gap) {
            // Stands in for per-square tooltips, which the canvas can't carry.
            Text(hovered.map(helpText) ?? "").lineLimit(1)
            Spacer()
            Text("Less").padding(.trailing, WalletMetrics.tight)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.color(level: level))
                    .frame(width: Self.cell, height: Self.cell)
            }
            Text("More").padding(.leading, WalletMetrics.tight)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func helpText(_ cell: DrinkingHeatmap.Cell) -> String {
        let date = cell.day.date(in: calendar).formatted(.dateTime.month(.abbreviated).day().year())
        guard cell.level > 0 else { return "\(date): alcohol-free" }
        guard let drinks = cell.drinks else { return "\(date): drinking day" }
        return "\(date): \(drinks == 1 ? "1 drink" : "\(drinks) drinks")"
    }

    static func color(level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.18)
        case 1: DrinkingDaysView.tint.opacity(0.35)
        case 2: DrinkingDaysView.tint.opacity(0.55)
        case 3: DrinkingDaysView.tint.opacity(0.78)
        default: DrinkingDaysView.tint
        }
    }
}

private struct DrinkingCalendar: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let select: (DayKey) -> Void

    /// A plain grid, not a lazy one: a lazy grid inside a list row misjudges its height as the row is
    /// reused, which made the list jump while scrolling. A month is at most 42 cells.
    var body: some View {
        let calendar = viewModel.calendar
        let today = viewModel.today
        Grid(horizontalSpacing: WalletMetrics.tight, verticalSpacing: WalletMetrics.tight) {
            GridRow {
                ForEach(Array(weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            ForEach(Array(weeks(calendar).enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = week[column] {
                            dayButton(day, today: today, calendar: calendar)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, WalletMetrics.small)
    }

    private func dayButton(_ day: DayKey, today: DayKey, calendar: Calendar) -> some View {
        let entry = viewModel.days[day]
        let isFuture = day > today
        return Button { select(day) } label: {
            DayCell(day: day.day, isMarked: entry != nil, isToday: day == today, isFuture: isFuture)
        }
        .buttonStyle(.plain)
        .disabled(isFuture || viewModel.isSaving)
        .accessibilityLabel(Text(day.date(in: calendar), format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(entry == nil ? "Alcohol-free" : "Drinking day")
        .accessibilityAddTraits(entry != nil ? .isSelected : [])
    }

    /// The month's days in rows of seven, padded with `nil` before the first and after the last.
    private func weeks(_ calendar: Calendar) -> [[DayKey?]] {
        var cells: [DayKey?] = Array(repeating: nil, count: leadingBlanks(calendar)) + monthDays(calendar)
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
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
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.hair)
        .contentShape(Rectangle())
    }
}
