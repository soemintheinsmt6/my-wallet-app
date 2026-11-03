import SwiftUI
import WalletDomain

/// Savings goals with their progress, projection and contribution history.
public struct GoalsView: View {
    @ObservedObject private var viewModel: DebtsViewModel
    @State private var editing: SavingsGoal?
    @State private var contributing: GoalProgress?
    @State private var deleting: GoalProgress?
    /// The goal whose celebration is showing, so it plays once rather than on every redraw.
    @State private var celebrating: UUID?
    @Environment(\.mainCurrency) private var mainCurrency

    public init(viewModel: DebtsViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            ForEach(viewModel.goals) { progress in
                Section {
                    Button { editing = progress.goal } label: { row(progress) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("Add", systemImage: "plus") { contributing = progress }.tint(.green)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { deleting = progress }
                        }
                    Button("Add Money", systemImage: "plus.circle.fill") { contributing = progress }
                        .font(.body.weight(.medium))
                    if !progress.contributions.isEmpty { history(progress) }
                }
            }
        }
        .overlay {
            if viewModel.goals.isEmpty && !viewModel.isLoading {
                WalletEmptyState(title: "No savings goals", symbol: "target",
                                 message: "Set a target and track what you put aside toward it.",
                                 actionTitle: "Add Goal") { editing = SavingsGoal(currencyCode: mainCurrency) }
            }
        }
        .overlay {
            if let celebrating, viewModel.goals.contains(where: { $0.goal.id == celebrating && $0.isAchieved }) {
                GoalCelebration()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .navigationTitle("Goals")
        .toolbar { Button("Add Goal", systemImage: "plus") { editing = SavingsGoal(currencyCode: mainCurrency) } }
        .sheet(item: $editing) { GoalEditorView(viewModel: viewModel, goal: $0) }
        .sheet(item: $contributing) { GoalContributionView(viewModel: viewModel, progress: $0) }
        .alert("Delete Goal?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let progress = deleting else { return }
                Task {
                    do { try await viewModel.deleteGoal(id: progress.goal.id) }
                    catch { viewModel.errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("Its contribution history is removed too. Any transfers created are kept.")
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
        .disabled(viewModel.isSaving)
        // Celebrate the moment a goal is first reached, then let it fade.
        .onChange(of: viewModel.goals.filter(\.isAchieved).map(\.id)) { previous, achieved in
            guard let newlyDone = achieved.first(where: { !previous.contains($0) }) else { return }
            withAnimation { celebrating = newlyDone }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { celebrating = nil }
            }
        }
    }

    private func row(_ progress: GoalProgress) -> some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.goal.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: WalletMetrics.small)
                if progress.isAchieved {
                    Label("Reached", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else if progress.isBehindSchedule() {
                    Text("Behind schedule")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            GoalRing(fraction: progress.fraction, isAchieved: progress.isAchieved)

            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.saved.walletFormatted(progress.goal.currencyCode)) of \(progress.goal.targetAmount.walletFormatted(progress.goal.currencyCode))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: WalletMetrics.small)
                Text(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            Text(projection(progress))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, WalletMetrics.tight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Says in words where the goal stands; the ring only reinforces it.
    private func projection(_ progress: GoalProgress) -> String {
        if progress.isAchieved { return "Target reached." }
        let remaining = progress.remaining.walletFormatted(progress.goal.currencyCode)
        guard let date = progress.projectedCompletion() else {
            if let deadline = progress.goal.deadline {
                return "\(remaining) to go by \(deadline.formatted(date: .abbreviated, time: .omitted))."
            }
            return "\(remaining) to go. Add a contribution to see a projection."
        }
        let projected = date.formatted(date: .abbreviated, time: .omitted)
        guard let deadline = progress.goal.deadline else {
            return "\(remaining) to go — on track for \(projected) at your current rate."
        }
        let target = deadline.formatted(date: .abbreviated, time: .omitted)
        return progress.isBehindSchedule()
            ? "\(remaining) to go — at this rate \(projected), after your \(target) deadline."
            : "\(remaining) to go — on track for \(projected), before your \(target) deadline."
    }

    private func history(_ progress: GoalProgress) -> some View {
        DisclosureGroup("Contributions (\(progress.contributions.count))") {
            ForEach(progress.contributions.reversed()) { contribution in
                HStack {
                    Text(contribution.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    WalletAmountText.net(contribution.amount, currencyCode: progress.goal.currencyCode,
                                         font: .callout.weight(.medium))
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { try await viewModel.deleteContribution(id: contribution.id) }
                            catch { viewModel.errorMessage = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .font(.subheadline)
    }
}

/// A progress ring. Decorative: the row states saved, target and percentage in text.
struct GoalRing: View {
    let fraction: Double
    let isAchieved: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke((isAchieved ? Color.green : Color.accentColor).gradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 56, height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.default, value: fraction)
        .accessibilityHidden(true)
    }
}

/// A brief flourish when a goal is first reached. Honors Reduce Motion by holding still.
struct GoalCelebration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: WalletMetrics.medium) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .scaleEffect(reduceMotion ? 1 : (isExpanded ? 1 : 0.6))
                .opacity(isExpanded ? 1 : 0)
            Text("Goal reached")
                .font(.title3.weight(.semibold))
                .opacity(isExpanded ? 1 : 0)
        }
        .padding(WalletMetrics.xxLarge)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(duration: 0.5)) { isExpanded = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal reached")
    }
}
