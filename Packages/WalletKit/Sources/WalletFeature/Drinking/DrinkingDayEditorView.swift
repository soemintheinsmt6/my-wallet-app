import SwiftUI
import WalletDomain

struct DrinkingDayEditorView: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let day: DayKey
    let existing: DrinkingDay?
    @Environment(\.dismiss) private var dismiss
    /// Zero means the count was not recorded.
    @State private var drinks: Int
    @State private var note: String
    @State private var errorMessage: String?

    init(viewModel: DrinkingDaysViewModel, day: DayKey, existing: DrinkingDay?) {
        self.viewModel = viewModel
        self.day = day
        self.existing = existing
        _drinks = State(initialValue: existing?.drinks ?? 0)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $drinks, in: 0...DrinkingDay.maximumDrinks) {
                        HStack {
                            Text("Drinks")
                            Spacer()
                            Text(drinks == 0 ? "Not recorded" : "\(drinks)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text("The number of drinks is optional. Leave it at Not recorded to just mark the day.")
                }
                if existing != nil {
                    Section {
                        WalletDestructiveRow(title: "Mark as Alcohol-free", symbol: "leaf") {
                            Task { await unmark() }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).accessibilityLabel("Error: \(errorMessage)") }
                }
            }
            .formStyle(.grouped)
            .disabled(viewModel.isSaving)
            .navigationTitle(Text(day.date(in: viewModel.calendar), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if viewModel.isSaving { ProgressView() } else { Text(existing == nil ? "Mark" : "Save") }
                    }
                    .disabled(viewModel.isSaving || note.count > DrinkingDay.maximumNoteLength)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    private func save() async {
        errorMessage = nil
        do {
            try await viewModel.mark(day, drinks: drinks == 0 ? nil : drinks, note: note)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func unmark() async {
        errorMessage = nil
        do {
            try await viewModel.unmark(day)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
