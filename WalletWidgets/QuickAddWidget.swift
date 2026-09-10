import SwiftUI
import WalletDomain
import WidgetKit

/// Buttons that open the record editor with a kind preselected.
///
/// Adding a record needs an amount and a category, so the widget hands off to the app through a
/// deep link rather than writing anything from the extension. `Link` gives each button its own
/// destination; a single `widgetURL` could only carry one.
struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletQuickAddWidget", provider: WalletProvider()) { entry in
            QuickAddWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Jump straight into adding an expense, income or transfer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var kinds: [RecordKind] {
        family == .systemSmall ? [.expense, .income] : [.expense, .income, .transfer]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Add")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if family == .systemSmall {
                ForEach(kinds, id: \.self) { button($0, compact: true) }
            } else {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { button($0, compact: false) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(_ kind: RecordKind, compact: Bool) -> some View {
        Link(destination: WalletDeepLink.addRecord(kind).url) {
            if compact {
                HStack(spacing: 8) {
                    WidgetIconTile(symbol: kind.widgetSymbol, color: kind.widgetTint, size: 22)
                    Text(kind.rawValue.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .frame(maxWidth: .infinity)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 5) {
                    WidgetIconTile(symbol: kind.widgetSymbol, color: kind.widgetTint, size: 28)
                    Text(kind.rawValue.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .accessibilityLabel("Add \(kind.rawValue)")
    }
}
