import Charts
import SwiftUI

/// The grid every chart draws: dotted lines in both directions, so the gridlines recede behind the
/// data rather than competing with it. Shared so the Dashboard and Statistics charts match.
enum WalletChartGrid {
    /// Round dots: zero-length dashes drawn with round caps, spaced a few points apart.
    static let stroke = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0, 3])

    /// How charts grow in when Statistics first shows its data.
    static let reveal = Animation.smooth(duration: 0.7)

    /// How charts move to new data when a control changes what they show: the period, its arrows,
    /// the grouping, the currency, the filters or the nature picker.
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

    /// A dotted vertical gridline at each date mark, with the default tick and label.
    static func dottedDateAxis(desiredCount: Int) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
            AxisGridLine(stroke: stroke)
            AxisTick()
            AxisValueLabel()
        }
    }
}
