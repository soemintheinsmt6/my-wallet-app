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
                        drinksControl
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

    /// The drinking day editor's orange circles, small: the count between them in orange, or
    /// Not recorded at zero. VoiceOver reads and adjusts it as one value.
    private var drinksControl: some View {
        // Tight, since each circle already sits in a wider tap area.
        HStack(spacing: 0) {
            Text("Drinks").foregroundStyle(.primary)
            Spacer()
            DrinkStepButton(symbol: "minus", label: "Fewer drinks", size: 32, font: .subheadline.weight(.bold),
                            isEnabled: drinks > 0) { drinks -= 1 }
            Group {
                if drinks == 0 {
                    Text("Not recorded").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(drinks, format: .number)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DrinkingDaysView.tint)
                        .contentTransition(.numericText(value: Double(drinks)))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .frame(minWidth: 36)
            DrinkStepButton(symbol: "plus", label: "More drinks", size: 32, font: .subheadline.weight(.bold),
                            isEnabled: drinks < DrinkingDay.maximumDrinks) { drinks += 1 }
        }
        .animation(.snappy, value: drinks)
        .frame(minHeight: WalletMetrics.touchTarget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drinks")
        .accessibilityValue(drinks == 0 ? "Not recorded" : "\(drinks)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: drinks = min(drinks + 1, DrinkingDay.maximumDrinks)
            case .decrement: drinks = max(drinks - 1, 0)
            @unknown default: break
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
