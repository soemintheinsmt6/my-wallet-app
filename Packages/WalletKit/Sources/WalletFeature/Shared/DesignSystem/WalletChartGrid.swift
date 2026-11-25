import Charts
import SwiftUI

/// The grid every chart draws: dotted lines in both directions, so the gridlines recede behind the
/// data rather than competing with it. Shared so the Dashboard and Statistics charts match.
enum WalletChartGrid {
    /// Round dots: zero-length dashes drawn with round caps, spaced a few points apart.
    static let stroke = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0, 3])

    /// How charts grow in when Statistics first shows its data.
    static let reveal = Animation.smooth(duration: 0.7)

    /// The Dashboard's reveal: quicker than Statistics', since it plays on every launch.
    static let dashboardReveal = Animation.smooth(duration: 0.5)

    /// How charts move to new data when a control changes what they show: the period, its arrows,
    /// the grouping, the currency, the filters or the nature picker. Budgets' month arrows and an
    /// account's period picker and arrows use it too, so every period change moves alike.
    static let change = Animation.smooth(duration: 0.45)

    /// The smallest round number at or above `value` (1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8 times a
    /// power of ten). Bars that grow in from zero need a fixed scale, or the axis would rescale
    /// with them; rounding it up keeps the top on a round figure the way an automatic scale does.
    static func niceCeiling(_ value: Double) -> Double {
        guard value > 0, value.isFinite else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        let step = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].first { $0 * magnitude >= value * (1 - 1e-9) } ?? 10
        return step * magnitude
    }

    /// A fixed scale from the data's range, rounded out to round figures and always including zero,
    /// for charts whose marks grow from zero.
    static func niceDomain(_ values: [Double]) -> ClosedRange<Double> {
        let low = values.min() ?? 0, high = values.max() ?? 0
        let lower = low < 0 ? -niceCeiling(-low) : 0
        let upper = high > 0 ? niceCeiling(high) : (low < 0 ? 0 : 1)
        return lower...upper
    }

    /// A dotted vertical gridline at each date mark, with the default tick and label.
    static func dottedDateAxis(desiredCount: Int) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
            AxisGridLine(stroke: stroke)
            AxisTick()
            AxisValueLabel()
        }
    }
}

/// Holds a screen's progress visuals at zero until `ready`, then grows them in once with
/// `animation` (at once with Reduce Motion), through `walletChartsRevealed`. For screens whose own
/// body does not need the flag; the Dashboard and Statistics keep their own, which their charts read.
private struct WalletChartsReveal: ViewModifier {
    let ready: Bool
    let animation: Animation
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.walletChartsRevealed, revealed)
            .onAppear(perform: reveal)
            .onChange(of: ready) { _, _ in reveal() }
    }

    private func reveal() {
        guard !revealed, ready else { return }
        if reduceMotion {
            revealed = true
        } else {
            withAnimation(animation) { revealed = true }
        }
    }
}

extension View {
    func walletChartsReveal(when ready: Bool, animation: Animation = WalletChartGrid.reveal) -> some View {
        modifier(WalletChartsReveal(ready: ready, animation: animation))
    }
}

private struct WalletChartsRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False while a screen waits to grow its charts in (the Dashboard and Statistics on first
    /// load): shared pieces such as `WalletSummaryCard`, `BudgetProgressRow` and the Dashboard's
    /// charts show zero until it turns true inside the reveal animation. True everywhere else.
    var walletChartsRevealed: Bool {
        get { self[WalletChartsRevealedKey.self] }
        set { self[WalletChartsRevealedKey.self] = newValue }
    }
}
