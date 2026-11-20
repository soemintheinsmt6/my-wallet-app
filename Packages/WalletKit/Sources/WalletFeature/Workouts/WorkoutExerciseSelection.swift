import SwiftUI
import WalletDomain

/// Tick the body parts and exercises a workout covered. Your own exercises come first, then the
/// presets under their body part; tapping a row toggles it and the list stays open.
struct WorkoutExerciseSelection: View {
    @ObservedObject var viewModel: WorkoutDaysViewModel
    @Binding var selection: [String]
    @State private var isAdding = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Button { newName = ""; isAdding = true } label: {
                HStack(spacing: WalletMetrics.medium) {
                    WalletIconTile(symbol: "plus", color: WorkoutDaysView.tint)
                    Text("Add Exercise").foregroundStyle(WorkoutDaysView.tint)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .walletFirstRow(true)

            let own = ownExercises
            if !own.isEmpty {
                Section("My Exercises") {
                    ForEach(own, id: \.self) { name in
                        row(name)
                            .swipeActions(allowsFullSwipe: false) {
                                if viewModel.customExercises.contains(name) {
                                    Button("Delete", role: .destructive) { delete(name) }
                                }
                            }
                    }
                }
            }

            ForEach(WorkoutExercises.presets) { group in
                Section(group.name) {
                    ForEach(group.exercises, id: \.self) { row($0) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(selection.isEmpty ? "Exercises" : "Exercises (\(selection.count))")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert("Add Exercise", isPresented: $isAdding) {
            TextField("Name", text: $newName)
            Button("Add") { add() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It joins My Exercises on all your devices and is ticked for this day.")
        }
        .alert("Unable to Update Exercises", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    /// The user's own list, plus any ticked name found in neither list (such as one deleted on
    /// another device), so it can still be unticked.
    private var ownExercises: [String] {
        let listed = Set((viewModel.customExercises + WorkoutExercises.presets.flatMap(\.exercises)).map { $0.lowercased() })
        let orphans = selection.filter { !listed.contains($0.lowercased()) }
        return WorkoutExercises.ordered(viewModel.customExercises + orphans)
    }

    private func isSelected(_ name: String) -> Bool {
        selection.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func row(_ name: String) -> some View {
        let selected = isSelected(name)
        return Button { toggle(name) } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(WorkoutDaysView.tint) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ name: String) {
        if isSelected(name) {
            selection.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            selection.append(name)
        }
    }

    private func add() {
        let name = newName
        Task {
            do {
                let added = try await viewModel.addExercise(name)
                if !isSelected(added) { selection.append(added) }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func delete(_ name: String) {
        Task {
            do { try await viewModel.deleteExercise(name) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
