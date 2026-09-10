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
            Section("Insights") {
                if let week = insights.week, week.current > 0 || week.previous > 0 {
                    comparisonRow("This week", week)
                }
                if let month = insights.month, month.current > 0 || month.previous > 0 {
                    comparisonRow("This month", month)
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

    private func comparisonRow(_ title: String, _ comparison: WalletInsights.Comparison) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: comparison.isHigher ? "arrow.up.right" : "arrow.down.right",
                           color: comparison.isHigher ? .orange : .green)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title).font(.body.weight(.medium))
                Text(detail(comparison))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: WalletMetrics.small)
            Text(comparison.current.walletFormatted(comparison.currencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }

    /// States the direction in words; the arrow and color only reinforce it.
    private func detail(_ comparison: WalletInsights.Comparison) -> String {
        guard let change = comparison.change else {
            return comparison.previous == 0 && comparison.current > 0
                ? "Nothing spent in the period before"
                : "No comparison available yet"
        }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let previous = comparison.previous.walletFormatted(comparison.currencyCode)
        return comparison.isHigher ? "\(percent) more than \(previous)" : "\(percent) less than \(previous)"
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
        .padding(.vertical, WalletMetrics.tight)
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
        .padding(.vertical, WalletMetrics.tight)
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
            if viewModel.preferences.weeklySummary {
                Picker("Send On", selection: $viewModel.preferences.weeklyWeekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(weekdayNames[day - 1]).tag(day)
                    }
                }
            }
            Toggle("Unusual Spending", isOn: $viewModel.preferences.unusualSpending)
            Toggle("Monthly Comparison", isOn: $viewModel.preferences.monthlyComparison)

            if viewModel.preferences.isAnyEnabled {
                Picker("Time of Day", selection: $viewModel.preferences.hour) {
                    ForEach(6...21, id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                Button("Enable System Notifications") {
                    Task { await viewModel.requestAuthorization() }
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
