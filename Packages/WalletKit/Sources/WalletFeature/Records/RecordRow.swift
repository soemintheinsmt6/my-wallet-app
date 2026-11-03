import SwiftUI
import WalletDomain

/// The record row shared by the records list and the Home dashboard.
///
/// Leading category tile, name, context line, trailing signed amount and a chevron — the same
/// rhythm as every other list in the app. Every use opens the record's editor, so the chevron is
/// part of the row rather than added at each call site.
struct RecordRow: View {
    @ObservedObject var viewModel: RecordsViewModel
    let record: WalletRecord
    /// Home shows records across days, so it needs the date; the grouped list only needs the time.
    var showsDate = false

    private var draft: RecordDraft { record.draft }

    private var title: String {
        if draft.isAdjustment, draft.categoryID == nil { return RecordDraft.adjustmentTitle }
        if draft.kind == .transfer, draft.categoryID == nil { return draft.kind.title }
        return viewModel.categoryName(draft.categoryID)
    }

    private var context: String {
        let account = viewModel.account(draft.accountID)?.name ?? "Unlinked account"
        if draft.kind == .transfer {
            let destination = viewModel.account(draft.destinationAccountID)?.name ?? "Unlinked account"
            return "\(account) → \(destination)"
        }
        if !draft.payee.isEmpty { return "\(account) · \(draft.payee)" }
        // An adjustment's note, such as "Interest", is usually the only thing saying what it was.
        if draft.isAdjustment, !draft.note.isEmpty { return "\(account) · \(draft.note)" }
        return account
    }

    private var timestamp: String {
        showsDate
            ? draft.date.formatted(date: .abbreviated, time: .shortened)
            : draft.date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            tile
            VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(context) · \(timestamp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: WalletMetrics.small)
            VStack(alignment: .trailing, spacing: WalletMetrics.hair) {
                WalletAmountText(amount: draft.amount, currencyCode: record.currencyCode, kind: draft.kind)
                if record.hasPhoto {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Has photo")
                }
            }
            WalletDisclosure()
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.vertical, WalletMetrics.tight)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var tile: some View {
        if let category = viewModel.category(draft.categoryID) {
            CategoryIcon(category: category)
        } else if draft.isAdjustment {
            WalletIconTile(symbol: RecordDraft.adjustmentSymbol, color: RecordDraft.adjustmentTint)
        } else {
            WalletIconTile(symbol: draft.kind.symbol, color: draft.kind.tint)
        }
    }
}
