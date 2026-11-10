import Charts
import SwiftUI

/// The grid every chart draws: dotted lines in both directions, so the gridlines recede behind the
/// data rather than competing with it. Shared so the Dashboard and Statistics charts match.
enum WalletChartGrid {
    /// Round dots: zero-length dashes drawn with round caps, spaced a few points apart.
    static let stroke = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0, 3])

    /// A dotted vertical gridline at each date mark, with the default tick and label.
    static func dottedDateAxis(desiredCount: Int) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: desiredCount)) { _ in
            AxisGridLine(stroke: stroke)
            AxisTick()
            AxisValueLabel()
        }
    }
}
