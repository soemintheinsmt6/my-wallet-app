import SwiftUI
import WalletDomain

/// Mark a day as a workout day, or edit or clear a marked one, in the record editor's layout:
/// the duration large on top, then the activity, day and note as rows.
struct WorkoutDayEditorView: View {
    @ObservedObject var viewModel: WorkoutDaysViewModel
    let day: DayKey
    let existing: WorkoutDay?
    @Environment(\.dismiss) private var dismiss
    /// A new day starts with the activity marked last, since most people repeat the same workouts.
    @AppStorage(WalletPreferenceKeys.lastWorkoutActivity) private var lastActivity = ""
    /// Zero means the duration was not recorded.
    @State private var minutes: Int
    @State private var activity: WorkoutActivity?
    @State private var note: String
    @State private var errorMessage: String?
    @State private var choosingActivity = false
    @State private var editingNote = false
    @ScaledMetric(relativeTo: .largeTitle) private var countFontSize = 60

    /// The minus and plus buttons move in five-minute steps.
    private static let step = 5

    init(viewModel: WorkoutDaysViewModel, day: DayKey, existing: WorkoutDay?) {
        self.viewModel = viewModel
        self.day = day
        self.existing = existing
        _minutes = State(initialValue: existing?.minutes ?? 0)
        _activity = State(initialValue: existing?.activity)
        _note = State(initialValue: existing?.note ?? "")
    }

    private var date: Date { day.date(in: viewModel.calendar) }

    /// "Wed, 11 Nov", with the year only when the day is not in the current one.
    private var dayFormat: Date.FormatStyle {
        let short = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        return viewModel.calendar.isDate(date, equalTo: .now, toGranularity: .year) ? short : short.year()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    durationSection
                    WalletEditorSectionHeader(title: "General")
                    RecordFormRow(symbol: activity?.symbol ?? WorkoutActivity.unspecifiedSymbol) {
                        WalletEditorNavigationButton(title: "Activity", value: activity?.title) {
                            choosingActivity = true
                        }
                    }
                    RecordFormRow(symbol: "calendar") {
                        Text("Day")
                        Spacer()
                        Text(date, format: dayFormat)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    RecordFormRow(symbol: "square.and.pencil", showsDivider: false) {
                        WalletEditorNavigationButton(title: "Note", value: note.isEmpty ? nil : note) {
                            editingNote = true
                        }
                    }
                    WalletEditorCaption("Time and activity are optional. Leave them empty to just mark the day.")
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                    if existing != nil {
                        WalletEditorDeleteButton(title: "Remove Workout") { Task { await unmark() } }
                    }
                }
                .walletEditorRows()
            }
            .walletEditorPage()
            .disabled(viewModel.isSaving)
            .navigationTitle(existing == nil ? "Mark Workout Day" : "Edit Workout Day")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $choosingActivity) {
                WorkoutActivitySelection(selection: $activity)
            }
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
                    .disabled(viewModel.isSaving || note.count > WorkoutDay.maximumNoteLength)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .onAppear {
                if existing == nil, activity == nil, !lastActivity.isEmpty {
                    activity = WorkoutActivity(rawValue: lastActivity)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 460)
        #endif
    }

    /// The minutes in the workout tint, between minus and plus; zero reads Not recorded.
    private var durationSection: some View {
        VStack(spacing: 4) {
            Text("Time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            HStack(spacing: WalletMetrics.large) {
                stepButton(symbol: "minus", label: "Less time", isEnabled: minutes > 0) { minutes = Self.stepDown(minutes) }
                Group {
                    if minutes == 0 {
                        Text("Not recorded")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: WalletMetrics.tight) {
                            Text(minutes, format: .number)
                                .font(.system(size: countFontSize))
                                .foregroundStyle(WorkoutDaysView.tint)
                                .contentTransition(.numericText(value: Double(minutes)))
                            Text("min")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: countFontSize * 1.2)
                stepButton(symbol: "plus", label: "More time", isEnabled: minutes < WorkoutDay.maximumMinutes) {
                    minutes = Self.stepUp(minutes)
                }
            }
            .animation(.snappy, value: minutes)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time")
        .accessibilityValue(minutes == 0 ? "Not recorded" : workoutDurationText(minutes: minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = Self.stepUp(minutes)
            case .decrement: minutes = Self.stepDown(minutes)
            @unknown default: break
            }
        }
    }

    /// To the next multiple of the step, so a synced odd value such as 42 snaps to 45.
    static func stepUp(_ minutes: Int) -> Int {
        min((minutes / step + 1) * step, WorkoutDay.maximumMinutes)
    }

    /// To the previous multiple of the step, so 42 goes to 40; stops at zero, Not recorded.
    static func stepDown(_ minutes: Int) -> Int {
        max(((minutes - 1) / step) * step, 0)
    }

    private func stepButton(symbol: String, label: String, isEnabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(WorkoutDaysView.tint.opacity(0.15)))
                .foregroundStyle(WorkoutDaysView.tint)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func save() async {
        errorMessage = nil
        do {
            try await viewModel.mark(day, minutes: minutes == 0 ? nil : minutes, activity: activity, note: note)
            if let activity { lastActivity = activity.rawValue }
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

/// The activity list behind the editor's Activity row, with None to leave it unset.
private struct WorkoutActivitySelection: View {
    @Binding var selection: WorkoutActivity?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            option(nil, title: "None", symbol: WorkoutActivity.unspecifiedSymbol)
                .walletFirstRow(true)
            ForEach(WorkoutActivity.allCases) { activity in
                option(activity, title: activity.title, symbol: activity.symbol)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Activity")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func option(_ activity: WorkoutActivity?, title: String, symbol: String) -> some View {
        Button {
            selection = activity
            dismiss()
        } label: {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: symbol, color: activity == nil ? .gray : WorkoutDaysView.tint)
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection == activity { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == activity ? .isSelected : [])
    }
}
