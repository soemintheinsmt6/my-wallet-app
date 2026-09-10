import SwiftUI
import WalletDomain

struct RecurrenceFields: View {
    @Binding var rule: RecurrenceRule?
    let start: Date
    var allowDisabling = true
    var body: some View {
        if allowDisabling { Toggle("Repeat", isOn: Binding(get: { rule != nil }, set: { rule = $0 ? RecurrenceRule() : nil })) }
        if rule != nil {
            Picker("Frequency", selection: Binding(get: { rule?.frequency ?? .monthly }, set: { rule?.frequency = $0 })) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle("End after a count", isOn: Binding(get: { rule?.count != nil }, set: { rule?.count = $0 ? 12 : nil }))
            if rule?.count != nil {
                Stepper("Occurrences: \(rule?.count ?? 1)", value: Binding(get: { rule?.count ?? 1 }, set: { rule?.count = $0 }), in: 1...100_000)
            }
            Toggle("End on a date", isOn: Binding(get: { rule?.endDate != nil }, set: { rule?.endDate = $0 ? start.addingTimeInterval(86400 * 365) : nil }))
            if rule?.endDate != nil {
                DatePicker("Last occurrence on or before", selection: Binding(get: { rule?.endDate ?? start }, set: { rule?.endDate = $0 }), in: start...)
            }
        }
    }
}
