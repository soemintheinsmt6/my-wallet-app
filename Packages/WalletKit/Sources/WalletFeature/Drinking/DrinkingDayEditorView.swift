import SwiftUI
import WalletDomain

/// Mark a day as a drinking day, or edit or clear a marked one, in the record editor's layout:
/// the count large on top, then the day and note as rows.
struct DrinkingDayEditorView: View {
    @ObservedObject var viewModel: DrinkingDaysViewModel
    let day: DayKey
    let existing: DrinkingDay?
    @Environment(\.dismiss) private var dismiss
    /// Zero means the count was not recorded.
    @State private var drinks: Int
    @State private var places: [String]
    @State private var note: String
    @State private var errorMessage: String?
    @State private var editingNote = false
    @State private var editingPlaces = false
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize = 60

    init(viewModel: DrinkingDaysViewModel, day: DayKey, existing: DrinkingDay?) {
        self.viewModel = viewModel
        self.day = day
        self.existing = existing
        _drinks = State(initialValue: existing?.drinks ?? 0)
        _places = State(initialValue: existing?.places ?? [])
        _note = State(initialValue: existing?.note ?? "")
    }

    private var date: Date { day.date(in: viewModel.calendar) }

    /// "Wed, 11 Nov", with the year only when the day is not in the current one.
    private var dayFormat: Date.FormatStyle {
        let short = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        let calendar = viewModel.calendar
        return calendar.isDate(date, equalTo: .now, toGranularity: .year) ? short : short.year()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    countSection
                    WalletEditorSectionHeader(title: "General")
                    RecordFormRow(symbol: "calendar") {
                        Text("Day")
                        Spacer()
                        Text(date, format: dayFormat)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    RecordFormRow(symbol: "mappin.and.ellipse") {
                        WalletEditorNavigationButton(title: "Places",
                                                     value: places.isEmpty ? nil : places.joined(separator: ", ")) {
                            editingPlaces = true
                        }
                    }
                    RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Note", value: note.isEmpty ? nil : note) {
                            editingNote = true
                        }
                    }
                    WalletEditorCaption("The number of drinks and places are optional. Leave them empty to just mark the day.")
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                    if existing != nil { alcoholFreeButton }
                }
                .walletEditorRows()
            }
            .walletEditorPage()
            .disabled(viewModel.isSaving)
            .navigationTitle(existing == nil ? "Mark Drinking Day" : "Edit Drinking Day")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $editingNote) {
                RecordTextEntry(title: "Note", text: $note, caption: "Add note", multiline: true)
            }
            .navigationDestination(isPresented: $editingPlaces) {
                DrinkingPlacesEntry(viewModel: viewModel, places: $places)
            }
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
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    /// The count in the drinking days' orange, between minus and plus; zero reads Not recorded.
    private var countSection: some View {
        VStack(spacing: 4) {
            Text("Drinks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            HStack(spacing: WalletMetrics.large) {
                stepButton(symbol: "minus", label: "Fewer drinks", isEnabled: drinks > 0) { drinks -= 1 }
                Group {
                    if drinks == 0 {
                        Text("Not recorded")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(drinks, format: .number)
                            .font(.system(size: countFontSize))
                            .foregroundStyle(DrinkingDaysView.tint)
                            .contentTransition(.numericText(value: Double(drinks)))
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: countFontSize * 1.2)
                stepButton(symbol: "plus", label: "More drinks", isEnabled: drinks < DrinkingDay.maximumDrinks) {
                    drinks += 1
                }
            }
            .animation(.snappy, value: drinks)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

    private func stepButton(symbol: String, label: String, isEnabled: Bool,
                            action: @escaping () -> Void) -> some View {
        DrinkStepButton(symbol: symbol, label: label, size: 52, font: .title2.weight(.semibold),
                        isEnabled: isEnabled, action: action)
    }

    /// The last row, where a saved item's delete sits in the other editors: clearing the mark.
    /// Green throughout, the alcohol-free green the summary tiles use, since an alcohol-free day is
    /// good news rather than a loss.
    private var alcoholFreeButton: some View {
        Button { Task { await unmark() } } label: {
            RecordFormRow(symbol: "leaf", color: .green, showsDivider: false) {
                Text("Mark as Alcohol-free").foregroundStyle(.green)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        errorMessage = nil
        do {
            try await viewModel.mark(day, drinks: drinks == 0 ? nil : drinks, places: places, note: note)
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

/// A minus or plus in an orange-tinted circle, held to repeat, faded when it cannot step further.
/// Large in the drinking day editor, small in the record editor's Drinks row.
struct DrinkStepButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    let font: Font
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .frame(width: size, height: size)
                .background(Circle().fill(DrinkingDaysView.tint.opacity(0.15)))
                .foregroundStyle(DrinkingDaysView.tint)
                // A small circle still gets a full-size tap area around it.
                .frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}
