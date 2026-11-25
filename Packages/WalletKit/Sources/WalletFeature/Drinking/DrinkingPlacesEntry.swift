import SwiftUI
import WalletDomain

/// The places a drinking day covered: a field to type one, the day's places ticked in the order
/// added, and places from earlier days below to tick in one tap. Ticking or adding keeps the
/// screen open, since a night out often spans several places; Done or Back returns to the editor.
struct DrinkingPlacesEntry: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    @Binding var places: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    /// The width of an icon tile, so tick circles line up with the field's plus tile.
    private static let leadingColumn: CGFloat = 36
    /// A navigation push takes about 0.35 seconds; raising the keyboard after it keeps the slide smooth.
    private static let pushDuration = Duration.milliseconds(400)

    private var typed: String { DrinkingDay.normalizedPlace(text) }
    private var isFull: Bool { places.count >= DrinkingDay.maximumPlaces }

    var body: some View {
        List {
            fieldRow.walletFirstRow(true)
            if !typed.isEmpty, !isAdded(typed) { addRow }
            if !places.isEmpty {
                header("This Day")
                ForEach(places, id: \.self) { place in
                    placeRow(place, selected: true)
                        .transition(.opacity)
                }
            }
            let offered = isFull ? [] : viewModel.placeSuggestions(for: text, excluding: places)
            if !offered.isEmpty {
                header(typed.isEmpty ? "Recent" : "Suggestions")
                ForEach(offered, id: \.self) { place in placeRow(place, selected: false) }
            }
            if isFull {
                WalletListFooter("A day can list up to \(DrinkingDay.maximumPlaces) places.")
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(places.isEmpty ? "Places" : "Places (\(places.count))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            await Task.yield()
            #if os(iOS)
            try? await Task.sleep(for: Self.pushDuration)
            guard !Task.isCancelled else { return }
            #endif
            if places.isEmpty { focused = true }
        }
    }

    private var fieldRow: some View {
        HStack(spacing: WalletMetrics.medium) {
            WalletIconTile(symbol: "mappin.and.ellipse", color: DrinkingDaysView.tint)
            TextField("Restaurant, bar or club", text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .focused($focused)
                .disabled(isFull)
                .onSubmit {
                    if typed.isEmpty { dismiss() } else { add(typed) }
                }
                .accessibilityLabel("Place name")
        }
        .frame(minHeight: WalletMetrics.touchTarget)
    }

    private var addRow: some View {
        let name = viewModel.placeSpelling(of: typed)
        let tooLong = name.count > DrinkingDay.maximumPlaceNameLength
        return Button { add(typed) } label: {
            HStack(spacing: WalletMetrics.medium) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DrinkingDaysView.tint)
                    .frame(width: Self.leadingColumn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                    Text("Add “\(name)”").foregroundStyle(DrinkingDaysView.tint).lineLimit(1)
                    if tooLong {
                        Text("Keep it under \(DrinkingDay.maximumPlaceNameLength) characters.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
            }
            .frame(minHeight: WalletMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFull || tooLong)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, WalletMetrics.medium)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    /// A tick circle in the icon column; tapping toggles the place and the screen stays open.
    private func placeRow(_ place: String, selected: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                if selected { places.removeAll { $0 == place } } else { add(place) }
            }
        } label: {
            HStack(spacing: WalletMetrics.medium) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(DrinkingDaysView.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: Self.leadingColumn)
                Text(place).foregroundStyle(.primary).lineLimit(1)
                Spacer()
            }
            .frame(minHeight: WalletMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(place)
        .accessibilityHint(selected ? "Removes it from this day" : "Adds it to this day")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func isAdded(_ name: String) -> Bool {
        let spelled = viewModel.placeSpelling(of: name)
        return places.contains { $0.compare(spelled, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// Adds the place under the spelling used before, once, and clears the field for the next one.
    private func add(_ name: String) {
        let place = viewModel.placeSpelling(of: name)
        guard !place.isEmpty, place.count <= DrinkingDay.maximumPlaceNameLength, !isFull, !isAdded(place) else { return }
        withAnimation(.snappy(duration: 0.2)) { places.append(place) }
        text = ""
    }
}
