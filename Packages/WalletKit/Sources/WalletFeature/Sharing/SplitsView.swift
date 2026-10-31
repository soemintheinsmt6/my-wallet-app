import SwiftUI
import WalletDomain

/// Shared expenses: who is up, who is down, and how to settle.
public struct SplitsView: View {
    @ObservedObject private var viewModel: SplitsViewModel

    public init(viewModel: SplitsViewModel) { self.viewModel = viewModel }

    private var balances: [(name: String, amount: Decimal)] {
        viewModel.balances
            .map { (name: $0.key, amount: $0.value) }
            .sorted { first, second in
                if first.amount != second.amount { return first.amount > second.amount }
                return first.name < second.name
            }
    }

    public var body: some View {
        List {
            if !balances.isEmpty {
                Section {
                    ForEach(balances, id: \.name) { entry in
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: entry.amount > 0 ? "arrow.down.left" : "arrow.up.right",
                                           color: entry.amount > 0 ? .green : .orange)
                            Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                            Spacer(minLength: WalletMetrics.small)
                            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                                Text(abs(entry.amount).walletFormatted(viewModel.currencyCode))
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                Text(entry.amount > 0 ? "is owed" : "owes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .padding(.vertical, WalletMetrics.tight)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Who owes what")
                } footer: {
                    WalletListFooter("Netted across every split record. A person is owed when they paid more than their share.")
                }
            }

            if !viewModel.settlements.isEmpty {
                Section {
                    ForEach(viewModel.settlements) { suggestion in
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: "arrow.right", color: .blue)
                            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                                Text("\(suggestion.from) pays \(suggestion.to)")
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: WalletMetrics.small)
                            Text(suggestion.amount.walletFormatted(viewModel.currencyCode))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .padding(.vertical, WalletMetrics.tight)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Settle up")
                } footer: {
                    WalletListFooter("The fewest payments that clear these balances. Recording them is up to you — they are suggestions, not transactions.")
                }
            }

            if !viewModel.splits.isEmpty {
                Section("Split records") {
                    ForEach(viewModel.splits) { split in
                        splitRow(split)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.splits.isEmpty {
                WalletEmptyState(title: "Nothing shared yet", symbol: "person.2.circle",
                                 message: "Split a record between people from its editor, and this screen keeps track of who owes what.")
            }
        }
        .navigationTitle("Shared")
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }

    private func splitRow(_ split: RecordSplit) -> some View {
        let record = viewModel.records.records.first { $0.id == split.recordID }
        return VStack(alignment: .leading, spacing: WalletMetrics.small) {
            HStack {
                Text(record.map { viewModel.records.categoryName($0.draft.categoryID) } ?? "Record")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: WalletMetrics.small)
                Text(split.total.walletFormatted(split.currencyCode))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            Text(split.participants.map(\.name).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Your share \(split.ownerShare.walletFormatted(split.currencyCode)) · \(split.method.title.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, WalletMetrics.tight)
        .swipeActions {
            Button("Remove Split", role: .destructive) {
                Task { await viewModel.delete(recordID: split.recordID) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Divides a record between people, from the record editor.
public struct SplitEditorView: View {
    @ObservedObject private var viewModel: SplitsViewModel
    private let recordID: UUID
    private let amount: Decimal
    private let currencyCode: String
    @Environment(\.dismiss) private var dismiss

    @State private var method = SplitMethod.equally
    @State private var participants: [SplitParticipant] = []
    @State private var ownerID: UUID?
    @State private var payerID: UUID?
    @State private var errorMessage: String?

    public init(viewModel: SplitsViewModel, recordID: UUID, amount: Decimal, currencyCode: String) {
        self.viewModel = viewModel
        self.recordID = recordID
        self.amount = amount
        self.currencyCode = currencyCode
    }

    private var sharesTotal: Decimal { participants.reduce(0) { $0 + $1.share } }
    private var difference: Decimal { amount - sharesTotal }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Split", selection: $method) {
                        ForEach(SplitMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: method) { _, _ in redistribute() }
                } header: {
                    Text("Method")
                } footer: {
                    Text("The total to divide is \(amount.walletFormatted(currencyCode)).")
                }

                Section {
                    ForEach($participants) { $participant in
                        VStack(alignment: .leading, spacing: WalletMetrics.small) {
                            HStack {
                                TextField("Name", text: $participant.name)
                                if participant.id == ownerID {
                                    Text("You").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if method != .equally {
                                LabeledContent("Share") {
                                    TextField("0", value: $participant.share, format: .number)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        #if os(iOS)
                                            .keyboardType(.decimalPad)
                                        #endif
                                }
                            } else {
                                LabeledContent("Share",
                                               value: participant.share.walletFormatted(currencyCode))
                            }
                        }
                        .padding(.vertical, WalletMetrics.hair)
                    }
                    .onDelete { offsets in
                        participants.remove(atOffsets: offsets)
                        redistribute()
                    }
                    Button {
                        participants.append(SplitParticipant(name: ""))
                        redistribute()
                    } label: {
                        Label("Add Person", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text(balanceFooter)
                }

                Section {
                    WalletMenuPicker("Paid by", selection: $payerID,
                                     value: participants.first { $0.id == payerID }.map { $0.name.isEmpty ? "Unnamed" : $0.name } ?? "") {
                        ForEach(participants) { Text($0.name.isEmpty ? "Unnamed" : $0.name).tag(Optional($0.id)) }
                    }
                } header: {
                    Text("Who paid")
                } footer: {
                    Text("Whoever paid fronts the whole bill; everyone else owes their share of it.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Split Record")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(viewModel.isSaving)
                }
            }
            .task { load() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    private var balanceFooter: String {
        if difference == 0 { return "The shares add up to the total." }
        return difference > 0
            ? "\(difference.walletFormatted(currencyCode)) still unassigned."
            : "\(abs(difference).walletFormatted(currencyCode)) over the total."
    }

    private func load() {
        if let existing = viewModel.split(for: recordID) {
            method = existing.method
            participants = existing.participants
            ownerID = existing.ownerParticipantID
            payerID = existing.participants.first { $0.paid > 0 }?.id
            return
        }
        // A new split starts with the user and one other person.
        let me = SplitParticipant(name: "You")
        let other = SplitParticipant(name: "")
        participants = [me, other]
        ownerID = me.id
        payerID = me.id
        redistribute()
    }

    /// Recomputes equal shares; other methods keep whatever the user typed.
    private func redistribute() {
        guard method == .equally, !participants.isEmpty else { return }
        let shares = SplitCalculator.equalShares(total: amount, count: participants.count,
                                                 currencyCode: currencyCode)
        for index in participants.indices where index < shares.count {
            participants[index].share = shares[index]
        }
    }

    private func save() {
        // Only the payer put money in; everyone else owes their share.
        for index in participants.indices {
            participants[index].paid = participants[index].id == payerID ? amount : 0
        }
        let split = RecordSplit(recordID: recordID, method: method, participants: participants,
                                currencyCode: currencyCode, ownerParticipantID: ownerID)
        Task {
            do {
                try await viewModel.save(split, recordAmount: amount)
                dismiss()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
