import SwiftUI
import WalletDomain

/// The dashboard card: each account with something planned, its balance in a month and, when it
/// is forecast to fall below its threshold, when.
struct CashFlowForecastSection: View {
    @ObservedObject var planning: PlanningViewModel
    let previewLimit: Int
    /// Opens Planning, where the series and bills behind the forecast are edited.
    let openPlanning: () -> Void
    @State private var open: OpenForecast?

    private var forecasts: [AccountForecast] { planning.forecast() }

    var body: some View {
        let forecasts = forecasts
        Section {
            if forecasts.isEmpty {
                Text("Nothing planned in the next \(CashFlowForecaster.defaultDays) days. Recurring records and bills appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(forecasts.prefix(previewLimit)) { forecast in
                    Button { open = OpenForecast(id: forecast.id) } label: {
                        CashFlowForecastRow(forecast: forecast).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            WalletSectionHeader(title: "Next \(CashFlowForecaster.defaultDays) days",
                                actionTitle: "Planning", action: openPlanning)
        }
        .sheet(item: $open) { open in
            // Read again while open, so a bill paid elsewhere moves the forecast shown.
            if let forecast = planning.forecast().first(where: { $0.id == open.id }) {
                CashFlowForecastDetailView(forecast: forecast)
            } else {
                NavigationStack {
                    WalletEmptyState(title: "Nothing planned", symbol: "checkmark.circle",
                                     message: "This account has no recurring records or unpaid bills in the next \(CashFlowForecaster.defaultDays) days.")
                }
            }
        }
    }
}

/// The account whose forecast sheet is open.
private struct OpenForecast: Identifiable {
    let id: UUID
}

/// An account's forecast in one row: a warning in red when it falls below its threshold, else its
/// lowest point, and the balance it ends at.
struct CashFlowForecastRow: View {
    let forecast: AccountForecast

    private var code: String { forecast.account.currencyCode }

    private var summary: (text: String, isWarning: Bool) {
        if let below = forecast.firstBelowThreshold {
            let when = below.date <= forecast.start ? "now" : "on \(below.date.formatted(.dateTime.day().month(.abbreviated)))"
            return ("Falls to \(below.balance.walletFormatted(code)) \(when)", true)
        }
        if let lowest = forecast.lowest {
            return ("Lowest \(lowest.balance.walletFormatted(code)) on \(lowest.date.formatted(.dateTime.day().month(.abbreviated)))", false)
        }
        let count = forecast.events.count
        return ("\(count) planned \(count == 1 ? "item" : "items")", false)
    }

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: forecast.account.symbol, color: forecast.account.settings.color.tint)
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(forecast.account.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: WalletMetrics.tight) {
                    if summary.isWarning {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    Text(summary.text)
                }
                .font(.caption)
                .foregroundStyle(summary.isWarning ? Color.red : Color.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: WalletMetrics.small)
            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                Text(forecast.endingBalance.walletFormatted(code))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(forecast.endingBalance < 0 ? Color.red : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("in \(CashFlowForecaster.defaultDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WalletDisclosure()
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the planned items and the balance after each")
    }
}

/// An account's forecast in full: the balance today and at the end, the day-by-day balance, and
/// every planned item with the balance it leaves.
struct CashFlowForecastDetailView: View {
    let forecast: AccountForecast
    @Environment(\.dismiss) private var dismiss

    private var code: String { forecast.account.currencyCode }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        figure("Today", forecast.startingBalance)
                        Spacer()
                        figure("In \(CashFlowForecaster.defaultDays) days", forecast.endingBalance, trailing: true)
                    }
                    if let below = forecast.firstBelowThreshold, let threshold = forecast.threshold {
                        Label(warning(below, threshold: threshold), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    BalanceTrendChart(points: forecast.dailyBalances(), currencyCode: code)
                        .padding(.vertical, WalletMetrics.small)
                } footer: {
                    Text("Moved only by the recurring records and unpaid bills in Planning. A bill that a recurring "
                         + "expense of the same amount already pays within \(LedgerMatcher.postingLagDays) days is counted once.")
                }

                Section("Planned") {
                    ForEach(Array(zip(forecast.events, forecast.runningBalances)), id: \.0.id) { event, balance in
                        eventRow(event, balance: balance)
                    }
                }
            }
            .navigationTitle(forecast.account.name)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func figure(_ title: String, _ amount: Decimal, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: WalletMetrics.hair) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text(amount.walletFormatted(code))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func warning(_ below: AccountForecast.Point, threshold: Decimal) -> String {
        let limit = threshold == 0 ? "zero" : threshold.walletFormatted(code)
        guard below.date > forecast.start else { return "Already below \(limit)" }
        return "Falls below \(limit) on \(below.date.formatted(date: .abbreviated, time: .omitted)), to \(below.balance.walletFormatted(code))"
    }

    private func eventRow(_ event: ForecastEvent, balance: Decimal) -> some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: symbol(for: event), color: event.isOverdue ? .red : (event.amount < 0 ? .orange : .green))
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(detail(for: event))
                    .font(.caption)
                    .foregroundStyle(event.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: WalletMetrics.small)
            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                WalletAmountText(amount: abs(event.amount), currencyCode: code,
                                 kind: event.amount < 0 ? .expense : .income, font: .callout.weight(.semibold))
                Text(balance.walletFormatted(code))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(balance < (forecast.threshold ?? balance) ? Color.red : Color.secondary)
            }
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .accessibilityElement(children: .combine)
    }

    private func symbol(for event: ForecastEvent) -> String {
        switch event.source {
        case .recurring: "repeat"
        case .bill: event.isOverdue ? "exclamationmark.circle" : "calendar"
        }
    }

    private func detail(for event: ForecastEvent) -> String {
        let source = switch event.source {
        case .recurring: "Recurring"
        case .bill: "Bill"
        }
        let date = event.date.formatted(.dateTime.day().month(.abbreviated))
        guard event.isOverdue else { return "\(source) · \(date)" }
        return "\(source) · \(event.source.isBill ? "overdue" : "due"), counted today"
    }
}

private extension ForecastEvent.Source {
    var isBill: Bool {
        if case .bill = self { return true }
        return false
    }
}
