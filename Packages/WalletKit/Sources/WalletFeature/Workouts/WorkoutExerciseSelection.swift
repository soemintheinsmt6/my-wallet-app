import SwiftUI
import WalletDomain

/// Tick the body parts and exercises a workout covered. Your own exercises come first, then the
/// presets under their body part. Every group opens collapsed, its header counting what is ticked
/// inside; searching lists matches from all groups at once. Tapping a row toggles it and the list
/// stays open.
struct WorkoutExerciseSelection: View {
    @ObservedObject var viewModel: WorkoutDaysViewModel
    @Binding var selection: [String]
    @State private var expanded: Set<String> = []
    @State private var query = ""
    @State private var isAdding = false
    @State private var newName = ""
    @State private var errorMessage: String?

    private static let ownTitle = "My Exercises"

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                groups
            } else {
                searchResults
            }
        }
        .listStyle(.plain)
        .navigationTitle(selection.isEmpty ? "Exercises" : "Exercises (\(selection.count))")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        #else
        .searchable(text: $query, prompt: "Search exercises")
        #endif
        .alert("Add Exercise", isPresented: $isAdding) {
            TextField("Name", text: $newName)
            Button("Add") { add(newName) }
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

    // MARK: Groups

    @ViewBuilder private var groups: some View {
        addRow(title: "Add Exercise") { newName = ""; isAdding = true }
            .walletFirstRow(true)

        let own = ownExercises
        if !own.isEmpty {
            Section {
                if expanded.contains(Self.ownTitle) {
                    ForEach(own, id: \.self) { name in
                        row(name).swipeActions(allowsFullSwipe: false) { deleteAction(name) }
                    }
                }
            } header: {
                sectionHeader(Self.ownTitle, names: own)
            }
        }

        ForEach(WorkoutExercises.presets) { group in
            Section {
                if expanded.contains(group.name) {
                    ForEach(group.exercises, id: \.self) { row($0) }
                }
            } header: {
                sectionHeader(group.name, names: group.exercises)
            }
        }
    }

    /// The group's name, how many of its exercises are ticked, and a chevron that turns down when open.
    private func sectionHeader(_ title: String, names: [String]) -> some View {
        let isOpen = expanded.contains(title)
        let ticked = names.filter(isSelected).count
        return Button {
            withAnimation(.snappy) {
                if isOpen { expanded.remove(title) } else { expanded.insert(title) }
            }
        } label: {
            HStack(spacing: WalletMetrics.small) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if ticked > 0 {
                    Text("\(ticked)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(WorkoutDaysView.tint))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .frame(minHeight: WalletMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(isOpen ? "Expanded" : "Collapsed")\(ticked > 0 ? ", \(ticked) selected" : "")")
        .accessibilityAddTraits([.isHeader, .isButton])
    }

    // MARK: Search

    private var trimmedQuery: String { WorkoutExercises.normalizedName(query) }

    /// Matches from every group, each with the group it is under, so "press" finds both presses.
    @ViewBuilder private var searchResults: some View {
        let query = trimmedQuery
        let matches = allExercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if !matches.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
            addRow(title: "Add “\(query)”") { add(query) }
                .walletFirstRow(true)
        }
        ForEach(matches, id: \.name) { match in
            row(match.name, detail: match.group)
                .swipeActions(allowsFullSwipe: false) { deleteAction(match.name) }
        }
    }

    /// Your own exercises, then the presets, each once, with the group it belongs to.
    private var allExercises: [(name: String, group: String)] {
        var seen = Set<String>()
        let own = ownExercises.map { (name: $0, group: Self.ownTitle) }
        let presets = WorkoutExercises.presets.flatMap { group in group.exercises.map { (name: $0, group: group.name) } }
        return (own + presets).filter { seen.insert($0.name.lowercased()).inserted }
    }

    // MARK: Rows

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

    private func addRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: "plus", color: WorkoutDaysView.tint)
                Text(title).foregroundStyle(WorkoutDaysView.tint).lineLimit(1)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ name: String, detail: String? = nil) -> some View {
        let selected = isSelected(name)
        return Button { toggle(name) } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                Image(systemName: "checkmark")
                    .foregroundStyle(WorkoutDaysView.tint)
                    .opacity(selected ? 1 : 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Only the user's own exercises can be deleted; presets offer no action.
    @ViewBuilder private func deleteAction(_ name: String) -> some View {
        if viewModel.customExercises.contains(name) {
            Button("Delete", role: .destructive) { delete(name) }
        }
    }

    private func toggle(_ name: String) {
        if isSelected(name) {
            selection.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            selection.append(name)
        }
    }

    private func add(_ name: String) {
        Task {
            do {
                let added = try await viewModel.addExercise(name)
                if !isSelected(added) { selection.append(added) }
                query = ""
                // Shows where it went once the search clears.
                if WorkoutExercises.presetName(matching: added) == nil { expanded.insert(Self.ownTitle) }
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
