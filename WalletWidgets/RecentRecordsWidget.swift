import SwiftUI
import WalletDomain
import WidgetKit

/// The most recent records, each opening the app when tapped.
struct RecentRecordsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletRecentRecordsWidget", provider: WalletProvider()) { entry in
            RecentRecordsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recent Records")
        .description("Your most recent expenses, income and transfers.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct RecentRecordsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var limit: Int { family == .systemLarge ? 6 : 3 }
    private var records: [WalletSnapshot.Entry] {
        Array((entry.snapshot?.recent ?? []).prefix(limit))
    }

    var body: some View {
        Group {
            if records.isEmpty {
                WidgetEmptyState(message: "No records yet. Add your first expense.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(destination: WalletDeepLink.addRecord(.expense).url) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    ForEach(records) { record in
                        row(record)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(WalletDeepLink.records.url)
    }

    private func row(_ record: WalletSnapshot.Entry) -> some View {
        HStack(spacing: 8) {
            WidgetIconTile(symbol: record.symbol, color: record.tint, size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(record.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(record.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(record.kind.widgetSign + record.amount.widgetFormatted(record.currencyCode))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(record.kind == .transfer ? Color.primary : record.kind.widgetTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
