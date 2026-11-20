import SwiftUI
import WalletDomain

/// Tick the body parts and exercises a workout covered. Your own exercises come first, then the
/// presets under their body part. Each group is a row with an icon tile that opens and closes in
/// place, all closed at first, counting what is ticked inside; searching lists matches from every
/// group at once. Tapping an exercise toggles it and the list stays open.
struct WorkoutExerciseSelection: View {
    @ObservedObject var viewModel: WorkoutDaysViewModel
    @Binding var selection: [String]
    @State private var expanded: Set<String> = []
    @State private var query = ""
    @State private var isAdding = false
    @State private var newName = ""
    @State private var errorMessage: String?

    private static let ownTitle = "My Exercises"
    /// The width of an icon tile, so tick circles sit in the same column as the group icons.
    private static let leadingColumn: CGFloat = 36

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

    /// Rows only, no sections: a plain list pads every section header with a tall gap, which spread
    /// the closed groups down the screen.
    @ViewBuilder private var groups: some View {
        addRow(title: "Add Exercise") { newName = ""; isAdding = true }
            .walletFirstRow(true)

        let own = ownExercises
        if !own.isEmpty {
            groupRow(Self.ownTitle, symbol: "star", names: own)
            if expanded.contains(Self.ownTitle) {
                ForEach(own, id: \.self) { name in
                    exerciseRow(name).swipeActions(allowsFullSwipe: false) { deleteAction(name) }
                }
            }
        }

        ForEach(WorkoutExercises.presets) { group in
            groupRow(group.name, symbol: group.symbol, names: group.exercises)
            if expanded.contains(group.name) {
                ForEach(group.exercises, id: \.self) { name in
                    // The body part itself leads its group; under its own name it would read twice.
                    exerciseRow(name, title: name == group.name ? "General" : name)
                }
            }
        }
    }

    /// The group's icon and name, how many of its exercises are ticked, and a chevron that turns
    /// down when open.
    private func groupRow(_ title: String, symbol: String, names: [String]) -> some View {
        let isOpen = expanded.contains(title)
        let ticked = names.filter(isSelected).count
        return Button {
            withAnimation(.snappy) {
                if isOpen { expanded.remove(title) } else { expanded.insert(title) }
            }
        } label: {
            HStack(spacing: WalletMetrics.medium) {
                WalletIconTile(symbol: symbol, color: WorkoutDaysView.tint)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if ticked > 0 {
                    Text("\(ticked)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(WorkoutDaysView.tint))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(isOpen ? "Expanded" : "Collapsed")\(ticked > 0 ? ", \(ticked) selected" : "")")
        .accessibilityAddTraits(.isButton)
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
            exerciseRow(match.name, detail: match.group)
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

    /// A tick circle in the icon column, then the name in line with the group titles above.
    private func exerciseRow(_ name: String, title: String? = nil, detail: String? = nil) -> some View {
        let selected = isSelected(name)
        return Button { withAnimation(.snappy(duration: 0.2)) { toggle(name) } } label: {
            HStack(spacing: WalletMetrics.medium) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(WorkoutDaysView.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.leadingColumn)
                Text(title ?? name).foregroundStyle(.primary)
                Spacer()
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title ?? name), \($0)" } ?? (title ?? name))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
