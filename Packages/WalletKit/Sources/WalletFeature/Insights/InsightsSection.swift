import SwiftUI
import WalletDomain

/// The Home dashboard's insights: how this week and month compare, anything unusual, and streaks.
struct InsightsSection: View {
    @ObservedObject var viewModel: InsightsViewModel
    /// Resolves category names; the calculator deals only in identifiers.
    let categoryTitle: (UUID) -> String

    private var insights: WalletInsights { viewModel.insights }

    var body: some View {
        if !insights.isEmpty {
            DashboardSection("Insights") {
                if let week = insights.week, week.current > 0 || week.previous > 0 {
                    comparisonRow("Spent this week", period: "last week", week)
                }
                if let month = insights.month, month.current > 0 || month.previous > 0 {
                    comparisonRow("Spent this month", period: "last month", month)
                }
                ForEach(insights.anomalies.prefix(2)) { anomaly in
                    anomalyRow(anomaly)
                }
                if insights.loggingStreak > 1 || insights.underBudgetStreak > 1 {
                    streakRow
                }
            }
        }
    }

    /// Spending so far in the period, said as spending, against the same point of the period
    /// before: the amount in red as an expense is, the arrow orange when spending rose.
    private func comparisonRow(_ title: String, period: String, _ comparison: WalletInsights.Comparison) -> some View {
        let higher = comparison.isHigherSoFar
        return HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: higher ? "arrow.up.right" : "arrow.down.right", color: higher ? .orange : .green)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title).font(.body.weight(.medium))
                Text(detail(comparison, period: period))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: WalletMetrics.small)
            // Nothing spent yet reads as a plain 0, not "−0" in red.
            WalletAmountText(amount: comparison.current, currencyCode: comparison.currencyCode,
                             kind: comparison.current > 0 ? .expense : nil, font: .subheadline.weight(.semibold))
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }

    /// States the direction and what it is compared with in words; the arrow and color only
    /// reinforce it. "12% more than last week at this point (46,400)".
    private func detail(_ comparison: WalletInsights.Comparison, period: String) -> String {
        guard let change = comparison.changeSoFar else {
            return comparison.current > 0 ? "Nothing spent by this point \(period)" : "Nothing spent yet"
        }
        let previous = comparison.previousSoFar.walletFormatted(comparison.currencyCode)
        if comparison.current == comparison.previousSoFar { return "Same as \(period) at this point (\(previous))" }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        return "\(percent) \(comparison.isHigherSoFar ? "more" : "less") than \(period) at this point (\(previous))"
    }

    private func anomalyRow(_ anomaly: WalletInsights.Anomaly) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: "exclamationmark.circle", color: .orange)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(categoryTitle(anomaly.categoryID))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Usually \(anomaly.average.walletFormatted(anomaly.currencyCode)) a month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: WalletMetrics.small)
            Text(anomaly.current.walletFormatted(anomaly.currencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(WalletMetrics.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unusual spending in \(categoryTitle(anomaly.categoryID))")
    }

    private var streakRow: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: "flame", color: .pink)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                if insights.loggingStreak > 1 {
                    Text("\(insights.loggingStreak)-day logging streak")
                        .font(.body.weight(.medium))
                }
                if insights.underBudgetStreak > 1 {
                    Text("\(insights.underBudgetStreak) days within every budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }
}

/// Settings controls for proactive notices.
struct InsightSettingsSection: View {
    @ObservedObject var viewModel: InsightsViewModel

    private var weekdayNames: [String] { Calendar.current.weekdaySymbols }

    var body: some View {
        Section {
            Toggle("Weekly Summary", isOn: $viewModel.preferences.weeklySummary)
                .refreshesNotificationAuthorization { await viewModel.refreshNotificationAuthorization() }
            if viewModel.preferences.weeklySummary {
                WalletMenuPicker("Send On", selection: $viewModel.preferences.weeklyWeekday,
                                 value: weekdayNames[viewModel.preferences.weeklyWeekday - 1]) {
                    ForEach(1...7, id: \.self) { day in
                        Text(weekdayNames[day - 1]).tag(day)
                    }
                }
            }
            Toggle("Unusual Spending", isOn: $viewModel.preferences.unusualSpending)
            Toggle("Monthly Comparison", isOn: $viewModel.preferences.monthlyComparison)

            if viewModel.preferences.isAnyEnabled {
                WalletMenuPicker("Time of Day", selection: $viewModel.preferences.hour,
                                 value: hourLabel(viewModel.preferences.hour)) {
                    ForEach(6...21, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                if !viewModel.notificationsAuthorized {
                    Button("Enable System Notifications") {
                        Task { await viewModel.requestAuthorization() }
                    }
                }
                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Insights")
        } footer: {
            Text("All off unless you turn them on. Unusual spending alerts once per category per month, comparing a category against its own recent average rather than against other categories.")
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
