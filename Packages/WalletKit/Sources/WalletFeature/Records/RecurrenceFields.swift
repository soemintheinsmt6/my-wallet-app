import SwiftUI
import WalletDomain

struct RecurrenceFields: View {
    /// Where these controls are being placed, which decides their chrome.
    enum Style {
        /// Bare rows for a `Form`, which draws its own grouping.
        case form
        /// Icon rows matching the record editor's hand-built scrolling layout.
        case rows
    }

    @Binding var rule: RecurrenceRule?
    let start: Date
    var allowDisabling = true
    var style: Style = .form

    var body: some View {
        switch style {
        case .form: formFields
        case .rows: rowFields
        }
    }

    @ViewBuilder private var formFields: some View {
        if allowDisabling { Toggle("Repeat", isOn: isRepeating) }
        if rule != nil {
            WalletMenuPicker("Frequency", selection: frequency, value: frequencyTitle) { frequencyOptions }
            Toggle("End after a count", isOn: endsAfterCount)
            if rule?.count != nil {
                Stepper("Occurrences: \(count.wrappedValue)", value: count, in: Self.countRange)
            }
            Toggle("End on a date", isOn: endsOnDate)
            if rule?.endDate != nil {
                DatePicker("Ends on or before", selection: endDate, in: start..., displayedComponents: .date)
            }
        }
    }

    /// Each limit keeps its value on the same row as its switch, so turning one on grows that row
    /// instead of pushing an unlabelled stepper or a squeezed date picker out below it.
    @ViewBuilder private var rowFields: some View {
        if allowDisabling {
            RecordFormRow(symbol: "repeat", showsDivider: rule != nil) {
                Toggle("Repeat", isOn: isRepeating)
            }
        }
        if rule != nil {
            RecordFormRow(symbol: "calendar.badge.clock") {
                WalletMenuPicker("Frequency", selection: frequency, value: frequencyTitle) { frequencyOptions }
            }
            RecordFormRow(symbol: "number") {
                VStack(spacing: WalletMetrics.small) {
                    Toggle("End after a count", isOn: endsAfterCount)
                    if rule?.count != nil {
                        HStack {
                            Text("Occurrences").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(count.wrappedValue)").monospacedDigit()
                            Stepper("Occurrences", value: count, in: Self.countRange).labelsHidden()
                        }
                    }
                }
            }
            RecordFormRow(symbol: "calendar.badge.checkmark") {
                VStack(spacing: WalletMetrics.small) {
                    Toggle("End on a date", isOn: endsOnDate)
                    if rule?.endDate != nil {
                        HStack {
                            Text("Ends on or before").foregroundStyle(.secondary)
                            Spacer()
                            DatePicker("Ends on or before", selection: endDate, in: start...,
                                       displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var frequencyOptions: some View {
        ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
    }

    private var frequencyTitle: String { frequency.wrappedValue.rawValue.capitalized }

    private static let countRange = 1...100_000

    /// A year out reads as a deliberate end rather than an accidental one.
    private var defaultEndDate: Date { start.addingTimeInterval(86400 * 365) }

    private var isRepeating: Binding<Bool> {
        Binding(get: { rule != nil }, set: { rule = $0 ? RecurrenceRule() : nil })
    }
    private var frequency: Binding<RecurrenceFrequency> {
        Binding(get: { rule?.frequency ?? .monthly }, set: { rule?.frequency = $0 })
    }
    private var endsAfterCount: Binding<Bool> {
        Binding(get: { rule?.count != nil }, set: { rule?.count = $0 ? 12 : nil })
    }
    private var count: Binding<Int> {
        Binding(get: { rule?.count ?? 1 }, set: { rule?.count = $0 })
    }
    private var endsOnDate: Binding<Bool> {
        Binding(get: { rule?.endDate != nil }, set: { rule?.endDate = $0 ? defaultEndDate : nil })
    }
    private var endDate: Binding<Date> {
        Binding(get: { rule?.endDate ?? defaultEndDate }, set: { rule?.endDate = $0 })
    }
}
