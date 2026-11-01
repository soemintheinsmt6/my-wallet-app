import SwiftUI

/// Steps a calendar period back and forward with the period named between the arrows.
///
/// Stepping whole periods is how people read statistics and reports; a raw date picker made the
/// user pick an arbitrary day inside the period they wanted. Forward stops at the current period.
struct WalletPeriodStepper: View {
    /// The period shown, such as "November 2026".
    let title: String
    /// The unit for the arrows' accessibility labels, such as "month".
    let unit: String
    /// The anchor date moved by the arrows.
    @Binding var date: Date
    let component: Calendar.Component

    private var interval: DateInterval? { Calendar.current.dateInterval(of: component, for: date) }

    private var isAtCurrentPeriod: Bool {
        guard let interval else { return true }
        return interval.contains(Date()) || interval.start > Date()
    }

    var body: some View {
        HStack {
            Button { shift(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: WalletMetrics.touchTarget, height: WalletMetrics.touchTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Previous \(unit)")

            Spacer()
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.identity)
            Spacer()

            Button { shift(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: WalletMetrics.touchTarget, height: WalletMetrics.touchTarget)
            }
            .buttonStyle(.borderless)
            .disabled(isAtCurrentPeriod)
            .accessibilityLabel("Next \(unit)")
        }
        .accessibilityElement(children: .contain)
        // The row leads with a button, so the list would start the separator at the title text;
        // start it at the row's edge like every other row.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    private func shift(by amount: Int) {
        guard let moved = Calendar.current.date(byAdding: component, value: amount, to: date) else { return }
        date = moved
    }
}
