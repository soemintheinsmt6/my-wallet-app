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
    @State private var note: String
    @State private var errorMessage: String?
    @State private var editingNote = false
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize = 60

    init(viewModel: DrinkingDaysViewModel, day: DayKey, existing: DrinkingDay?) {
        self.viewModel = viewModel
        self.day = day
        self.existing = existing
        _drinks = State(initialValue: existing?.drinks ?? 0)
        _note = State(initialValue: existing?.note ?? "")
    }

    private var date: Date { day.date(in: viewModel.calendar) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    countSection
                    WalletEditorSectionHeader(title: "General")
                    RecordFormRow(symbol: "calendar") {
                        Text("Day")
                        Spacer()
                        Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Note", value: note.isEmpty ? nil : note) {
                            editingNote = true
                        }
                    }
                    WalletEditorCaption("The number of drinks is optional. Leave it at Not recorded to just mark the day.")
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
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(DrinkingDaysView.tint.opacity(0.15)))
                .foregroundStyle(DrinkingDaysView.tint)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
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
