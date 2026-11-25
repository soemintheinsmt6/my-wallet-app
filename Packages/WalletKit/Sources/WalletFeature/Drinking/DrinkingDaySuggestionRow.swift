import SwiftUI
import WalletDomain

/// Offered in the record editor under an alcohol expense: a switch to mark the record's day as a
/// drinking day when it is not marked yet. Off until turned on, since it is only a suggestion.
struct DrinkingDaySuggestionRow: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let date: Date
    let payee: String
    @Binding var isOn: Bool

    var body: some View {
        if viewModel.canSuggestMarking(date) {
            VStack(spacing: 0) {
                RecordFormRow(symbol: "wineglass", color: DrinkingDaysView.tint, showsDivider: false) {
                    Toggle("Mark as Drinking Day", isOn: $isOn)
                        .tint(DrinkingDaysView.tint)
                }
                WalletEditorCaption(caption)
            }
        }
    }

    private var caption: String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let place = DrinkingDay.normalizedPlace(payee)
        return place.isEmpty
            ? "\(day) isn't marked as a drinking day yet."
            : "\(day) isn't marked as a drinking day yet. \(place) is added as its place."
    }
}
