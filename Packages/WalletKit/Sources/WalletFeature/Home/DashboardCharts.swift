import Charts
import SwiftUI
import WalletDomain

// MARK: - Data

/// One part of a breakdown: a category or label, its amount, and its identity color.
struct BreakdownEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let amount: Decimal
    let color: Color
}

enum DashboardBreakdown {
    /// Most slices a donut shows before the rest fold into "Other"; past this, neighbors blur.
    static let sliceLimit = 6

    /// Spending rolled up from subcategories to their top-level category, so the dashboard shows
    /// "Food & Drinks" rather than a sliver per subcategory. Largest first.
    static func byTopLevelCategory(_ totals: [CategoryTotal], categories: [WalletCategory]) -> [BreakdownEntry] {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var sums: [UUID?: Decimal] = [:]
        for total in totals {
            let category = total.categoryID.flatMap { byID[$0] }
            let root = category.map { $0.parentID.flatMap { byID[$0] } ?? $0 }
            sums[root?.id, default: 0] += total.amount
        }
        return sums.map { id, amount in
            let category = id.flatMap { byID[$0] }
            return BreakdownEntry(id: id?.uuidString ?? "uncategorized", name: category?.name ?? "Uncategorized",
                                  amount: amount, color: category?.colorToken.color ?? .gray)
        }
        .sorted(by: largestFirst)
    }

    static func byLabel(_ totals: [LabelTotal], tags: [WalletTag]) -> [BreakdownEntry] {
        let byID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        return totals.map { total in
            let tag = total.tagID.flatMap { byID[$0] }
            return BreakdownEntry(id: total.id, name: tag?.name ?? "No label", amount: total.amount,
                                  color: tag?.color.tint ?? .gray)
        }
        .sorted(by: largestFirst)
    }

    /// At most `limit` entries: the largest `limit - 1` keep their own color and the rest become
    /// one gray "Other". Colors stay with their entity, so folding never repaints a survivor.
    static func folded(_ entries: [BreakdownEntry], limit: Int = sliceLimit) -> [BreakdownEntry] {
        guard entries.count > limit else { return entries }
        let kept = Array(entries.prefix(limit - 1))
        let rest = entries.dropFirst(limit - 1).reduce(Decimal.zero) { $0 + $1.amount }
        return kept + [BreakdownEntry(id: "other", name: "Other", amount: rest, color: Color.secondary.opacity(0.5))]
    }

    private static func largestFirst(_ left: BreakdownEntry, _ right: BreakdownEntry) -> Bool {
        left.amount == right.amount ? left.name < right.name : left.amount > right.amount
    }
}

// MARK: - Balance trend

/// Total balance over the last 30 days as a single line over a light area. One series, so no
/// legend: the card title names it. Touch and drag to read a day's balance.
struct BalanceTrendChart: View {
    let points: [StatisticsPoint]
    let currencyCode: String
    @State private var selected: Date?

    private var selectedPoint: StatisticsPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Date", point.date, unit: .day),
                         y: .value("Balance", point.amount.doubleValue))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", point.date, unit: .day),
                         y: .value("Balance", point.amount.doubleValue))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if let point = selectedPoint {
                RuleMark(x: .value("Date", point.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    // Kept inside the plot, so it never covers the balance above the chart.
                    .annotation(position: .top, spacing: WalletMetrics.tight,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(spacing: WalletMetrics.hair) {
                            Text(point.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(point.amount.walletFormatted(currencyCode))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, WalletMetrics.small)
                        .padding(.vertical, WalletMetrics.tight)
                        // A solid card fill with a hairline edge: a material renders as solid
                        // black inside a chart annotation on device, hiding the text on it.
                        .background(Color.walletCard, in: RoundedRectangle(cornerRadius: WalletMetrics.small))
                        .overlay {
                            RoundedRectangle(cornerRadius: WalletMetrics.small)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    }
                PointMark(x: .value("Date", point.date, unit: .day),
                          y: .value("Balance", point.amount.doubleValue))
                    .symbolSize(64)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                // Solid hairlines: a dashed grid reads as a projection or a threshold.
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
            }
        }
        .frame(height: WalletMetrics.Chart.compactHeight + WalletMetrics.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance over the last 30 days")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "No data" }
        return "From \(first.amount.walletFormatted(currencyCode)) to \(last.amount.walletFormatted(currencyCode))"
    }
}

// MARK: - Expense breakdown

/// A donut of this month's expenses by category or by label, with the total in the hole and a
/// legend carrying every name, share and amount, so no part is identified by color alone.
struct ExpenseBreakdownView: View {
    enum Grouping: String, CaseIterable, Identifiable {
        case categories = "Categories"
        case labels = "Labels"
        var id: String { rawValue }
    }

    let byCategory: [BreakdownEntry]
    let byLabel: [BreakdownEntry]
    let total: Decimal
    let currencyCode: String
    @State private var grouping = Grouping.categories
    @AppStorage(WalletPreferenceKeys.numberScale) private var numberScale = NumberScale.automatic.rawValue

    private var entries: [BreakdownEntry] {
        DashboardBreakdown.folded(grouping == .categories ? byCategory : byLabel)
    }

    var body: some View {
        VStack(spacing: WalletMetrics.large) {
            Picker("Group by", selection: $grouping) {
                ForEach(Grouping.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if total <= 0 {
                Text("No expenses this month.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Chart(entries) { entry in
                    SectorMark(angle: .value("Amount", entry.amount.doubleValue),
                               innerRadius: .ratio(0.64), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(entry.color)
                        .accessibilityLabel(entry.name)
                        .accessibilityValue(entry.amount.walletFormatted(currencyCode))
                }
                .chartLegend(.hidden)
                .frame(height: WalletMetrics.Chart.donutHeight)
                .overlay {
                    let short = total.walletShort(currencyCode,
                                                  scale: NumberScale(rawValue: numberScale) ?? .automatic)
                    VStack(spacing: WalletMetrics.hair) {
                        Text("Total").font(.caption2).foregroundStyle(.secondary)
                        Text(short.value)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(short.unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: WalletMetrics.Chart.donutHeight * 0.64 - WalletMetrics.large)
                    .accessibilityHidden(true)
                }

                VStack(spacing: WalletMetrics.small) {
                    ForEach(entries) { entry in legendRow(entry) }
                }
            }
        }
        .padding(.vertical, WalletMetrics.small)
    }

    private func legendRow(_ entry: BreakdownEntry) -> some View {
        let share = total > 0 ? (entry.amount / total).doubleValue : 0
        return HStack(spacing: WalletMetrics.small) {
            Circle().fill(entry.color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(entry.name).lineLimit(1)
            Spacer(minLength: WalletMetrics.small)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(entry.amount.walletFormatted(currencyCode))
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Top expenses

/// This month's largest categories as ranked bars, each scaled to the largest, with its name and
/// amount written above it.
struct TopExpensesView: View {
    let entries: [BreakdownEntry]
    let currencyCode: String

    private var largest: Decimal { entries.first?.amount ?? 0 }

    var body: some View {
        VStack(spacing: WalletMetrics.medium) {
            if entries.isEmpty {
                Text("No expenses this month.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                    HStack {
                        Text(entry.name).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer(minLength: WalletMetrics.small)
                        Text(entry.amount.walletFormatted(currencyCode))
                            .font(.subheadline.weight(.medium))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    GeometryReader { proxy in
                        let fraction = largest > 0 ? (entry.amount / largest).doubleValue : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(entry.color)
                                .frame(width: max(proxy.size.width * fraction, 4))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, WalletMetrics.small)
    }
}
