import SwiftUI
import WalletDomain

/// Offered in the record editor under an alcohol expense: a switch to mark the record's day as a
/// drinking day when it is not marked yet. Off until turned on, since it is only a suggestion;
/// once on, the day's drinks and places can be filled in here, and saving the record saves both.
struct DrinkingDaySuggestionRow: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let date: Date
    let payee: String
    @Binding var isOn: Bool
    /// Zero means the count was not recorded.
    @Binding var drinks: Int
    /// `nil` until the places are edited here, and until then they follow the payee.
    @Binding var editedPlaces: [String]?
    @State private var editingPlaces = false

    private var places: [String] { editedPlaces ?? viewModel.places(forPayee: payee) }

    var body: some View {
        if viewModel.canSuggestMarking(date) {
            VStack(spacing: 0) {
                RecordFormRow(symbol: "wineglass", color: DrinkingDaysView.tint, showsDivider: isOn) {
                    Toggle("Mark as Drinking Day", isOn: $isOn.animation(.snappy))
                        .tint(DrinkingDaysView.tint)
                }
                if isOn {
                    RecordFormRow(symbol: "number", color: DrinkingDaysView.tint) {
                        Stepper(value: $drinks, in: 0...DrinkingDay.maximumDrinks) {
                            HStack {
                                Text("Drinks")
                                Spacer()
                                Text(drinks == 0 ? "Not recorded" : "\(drinks)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityValue(drinks == 0 ? "Not recorded" : "\(drinks)")
                    }
                    RecordFormRow(symbol: "mappin.and.ellipse", color: DrinkingDaysView.tint, showsDivider: false) {
                        WalletEditorNavigationButton(title: "Places",
                                                     value: places.isEmpty ? nil : places.joined(separator: ", ")) {
                            editingPlaces = true
                        }
                    }
                }
                WalletEditorCaption(caption)
            }
            .navigationDestination(isPresented: $editingPlaces) {
                DrinkingPlacesEntry(viewModel: viewModel,
                                    places: Binding(get: { places }, set: { editedPlaces = $0 }))
            }
        }
    }

    private var caption: String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return isOn
            ? "Saving also marks \(day) as a drinking day. Drinks and places are optional."
            : "\(day) isn't marked as a drinking day yet."
    }
}
