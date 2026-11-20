import SwiftUI
import WalletDomain

/// Sizes of the year chart, outside the view because a generic type cannot hold static storage.
private enum DayHeatmapMetrics {
    static let cell: CGFloat = 13
    static let gap: CGFloat = 3
    static let pitch = cell + gap
    static let labelHeight: CGFloat = 14
}

/// A contribution-chart year: weeks run left to right, weekdays top to bottom, and it opens
/// scrolled to the most recent week. Shared by Drinking Days and Workout Days.
struct DayHeatmapView<Cell: DayHeatmapCell>: View {
    let weeks: [[Cell?]]
    let monthLabels: [DayGrid.MonthLabel]
    /// The period's first day, which rebuilds the scroll view per period so it starts at its end.
    let first: DayKey
    let today: DayKey
    let calendar: Calendar
    let tint: Color
    let isDisabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    /// What a square holds, shown in the legend while hovering.
    let describe: (Cell) -> String
    let select: (DayKey) -> Void

    @State private var hovered: Cell?

    private typealias Metrics = DayHeatmapMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(alignment: .top, spacing: Metrics.gap) {
                weekdayLabels
                // An anchor rather than `scrollTo`, which also scrolls the enclosing list and threw it
                // back to the chart whenever the row reappeared. Rebuilt per period to start at its end.
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Metrics.gap) {
                        monthLabelRow
                        grid
                    }
                    .padding(.trailing, Metrics.gap)
                }
                .defaultScrollAnchor(.trailing)
                .id(first)
            }
            legend
        }
        .padding(.vertical, WalletMetrics.small)
        // 365 squares are too many to step through; the month view is the accessible way to edit.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Switch to Month to review or change individual days.")
    }

    /// Every other weekday is labelled, as GitHub does, to keep the column narrow.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Metrics.gap) {
            Color.clear.frame(width: 1, height: Metrics.labelHeight)
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 1 ? calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + row) % 7] : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(height: Metrics.cell)
            }
        }
    }

    private var monthLabelRow: some View {
        HStack(spacing: Metrics.gap) {
            ForEach(weeks.indices, id: \.self) { week in
                let label = monthLabels.first { $0.week == week }
                // Drawn at its natural width, overflowing into the following columns.
                Text(label.map { $0.month.date(in: calendar).formatted(.dateTime.month(.abbreviated)) } ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(width: Metrics.cell, height: Metrics.labelHeight, alignment: .leading)
            }
        }
    }

    /// Drawn as one canvas rather than a button per day: hundreds of views made the list stutter
    /// whenever the chart scrolled into view.
    private var grid: some View {
        Canvas { context, _ in
            for (week, column) in weeks.enumerated() {
                for (row, cell) in column.enumerated() {
                    guard let cell else { continue }
                    let rect = CGRect(x: CGFloat(week) * Metrics.pitch, y: CGFloat(row) * Metrics.pitch,
                                      width: Metrics.cell, height: Metrics.cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3, style: .continuous),
                                 with: .color(color(level: cell.level)))
                    if cell.day == today {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2.5, style: .continuous),
                                       with: .color(.primary), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: max(0, CGFloat(weeks.count) * Metrics.pitch - Metrics.gap), height: 7 * Metrics.pitch - Metrics.gap)
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

    private func cell(at location: CGPoint) -> Cell? {
        let week = Int(location.x / Metrics.pitch), row = Int(location.y / Metrics.pitch)
        guard location.x >= 0, location.y >= 0, weeks.indices.contains(week), (0..<7).contains(row) else { return nil }
        return weeks[week][row]
    }

    private var legend: some View {
        HStack(spacing: Metrics.gap) {
            // Stands in for per-square tooltips, which the canvas can't carry.
            Text(hovered.map(describe) ?? "").lineLimit(1)
            Spacer()
            Text("Less").padding(.trailing, WalletMetrics.tight)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(level: level))
                    .frame(width: Metrics.cell, height: Metrics.cell)
            }
            Text("More").padding(.leading, WalletMetrics.tight)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func color(level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.18)
        case 1: tint.opacity(0.35)
        case 2: tint.opacity(0.55)
        case 3: tint.opacity(0.78)
        default: tint
        }
    }
}
