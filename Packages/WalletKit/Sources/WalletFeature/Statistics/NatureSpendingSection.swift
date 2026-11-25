import Charts
import SwiftUI
import WalletDomain

/// How much of the period's spending was a must, a need or a want: a stacked chart over the
/// period, the total for the nature picked, and the categories behind it.
struct NatureSpendingSection: View {
    @ObservedObject var viewModel: RecordsViewModel
    let spending: NatureSpending
    let interval: DateInterval
    let grouping: StatisticsGranularity
    let periodTitle: String
    /// False until Statistics first has data; the bars, meters and total grow in from zero.
    let revealed: Bool
    let currencyCode: String
    let numberScale: NumberScale

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `nil` shows every nature.
    @State private var nature: CategoryNature?
    @State private var showsAllCategories = false

    private static let collapsedCount = 5

    var body: some View {
        Group {
            WalletListSectionHeader("Nature of spending")
            // Switching nature animates everything that depends on it: the bars restack and rescale,
            // the total rolls to its new figure, and category rows slide in and out.
            Picker("Nature", selection: $nature.animation(reduceMotion ? nil : WalletChartGrid.change)) {
                Text("All").tag(CategoryNature?.none)
                ForEach(NatureSpending.natures) { Text($0.title).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowInsets(EdgeInsets(top: WalletMetrics.small, leading: WalletMetrics.large,
                                      bottom: WalletMetrics.small, trailing: WalletMetrics.large))

            VStack(alignment: .leading, spacing: WalletMetrics.small) {
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text(periodTitle.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let total = revealed ? spending.total(nature) : 0
                    Text(total.walletFormatted(currencyCode))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: total.doubleValue))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .accessibilityElement(children: .combine)

                let points = spending.trend(nature)
                if points.isEmpty {
                    Text(nature == nil ? "No spending in this period." : "No \(nature!.title.lowercased()) spending in this period.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, WalletMetrics.small)
                } else {
                    chart(points)
                }
            }
            .padding(.vertical, WalletMetrics.small)

            categoryLines
            WalletListCaption("How much you must pay, need to pay, or just want to spend. Set a category's nature "
                              + "in Categories; spending in categories without one is left out.")
        }
        .onChange(of: nature) { _, _ in showsAllCategories = false }
    }

    private func chart(_ points: [NatureSpendingPoint]) -> some View {
        Chart(points) { point in
            BarMark(x: .value("Date", point.date, unit: grouping.component),
                    y: .value("Amount", revealed ? point.amount.doubleValue : 0))
                .foregroundStyle(by: .value("Nature", point.nature.title))
                .cornerRadius(WalletMetrics.tight)
                .accessibilityLabel("\(point.nature.title), \(point.date.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityValue(point.amount.walletFormatted(currencyCode))
        }
        .chartForegroundStyleScale(domain: NatureSpending.natures.map(\.title),
                                   range: NatureSpending.natures.map(\.tint))
        .chartLegend(nature == nil ? .visible : .hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...WalletChartGrid.niceCeiling(tallestStack(points)))
        .chartXAxis { WalletChartGrid.dottedDateAxis(desiredCount: 4) }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: WalletChartGrid.stroke)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.walletAxisLabel(currencyCode, scale: numberScale))
                    }
                }
            }
        }
        .frame(height: WalletMetrics.Chart.height)
    }

    /// The highest a step's stacked bar reaches, so the scale is fixed while the bars grow in.
    private func tallestStack(_ points: [NatureSpendingPoint]) -> Double {
        Dictionary(grouping: points, by: \.date).values
            .map { $0.reduce(0) { $0 + $1.amount.doubleValue } }
            .max() ?? 0
    }

    @ViewBuilder private var categoryLines: some View {
        let categories = spending.categories(nature)
        let peak = categories.first?.amount ?? 0
        let shown = showsAllCategories ? categories : Array(categories.prefix(Self.collapsedCount))
        ForEach(shown) { entry in
            VStack(alignment: .leading, spacing: WalletMetrics.small) {
                HStack(spacing: WalletMetrics.small) {
                    Text(viewModel.categoryName(entry.categoryID))
                        .lineLimit(1)
                    Spacer(minLength: WalletMetrics.small)
                    Text(entry.amount.walletFormatted(currencyCode)).monospacedDigit().lineLimit(1)
                }
                WalletProgressBar(value: revealed && peak > 0 ? (entry.amount / peak).doubleValue : 0,
                                  tint: viewModel.category(entry.categoryID)?.colorToken.color ?? .gray, height: 8)
            }
            .padding(.vertical, WalletMetrics.tight)
            .accessibilityElement(children: .combine)
        }
        if categories.count > Self.collapsedCount {
            // Trailing, as the debt screen's lists place it.
            HStack {
                Spacer()
                WalletExpandButton(isExpanded: showsAllCategories, count: categories.count) {
                    withAnimation { showsAllCategories.toggle() }
                }
                .accessibilityHint(showsAllCategories ? "Shows only the top \(Self.collapsedCount) categories"
                                                      : "Shows every category")
            }
            .frame(minHeight: WalletMetrics.touchTarget)
        }
    }
}
