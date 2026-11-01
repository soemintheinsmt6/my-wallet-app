import SwiftUI
import WalletDomain
import WidgetKit

/// Complications read the snapshot the watch app persisted into the shared App Group; the
/// extension cannot use WatchConnectivity itself.
struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        let snapshot = context.isPreview ? WalletSnapshot.preview : WalletSnapshotStore.read()
        completion(WalletEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        let entry = WalletEntry(date: Date(), snapshot: WalletSnapshotStore.read())
        // The watch app reloads timelines whenever the phone sends new state; hourly is a fallback.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WalletEntry: TimelineEntry {
    let date: Date
    let snapshot: WalletSnapshot?
}

/// Total balance on the watch face.
struct WatchBalanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletWatchBalance", provider: WatchComplicationProvider()) { entry in
            WatchBalanceComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Balance")
        .description("Your total balance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchBalanceComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var balance: WalletSnapshot.Balance? { entry.snapshot?.primaryBalance }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Balance").font(.caption2).foregroundStyle(.secondary)
                Text(compact).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
                if let month = entry.snapshot?.month {
                    Text("Spent today \(entry.snapshot?.todaySpend.complicationCompact(month.currencyCode) ?? "—")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 0) {
                Image(systemName: WalletSymbols.wallet).font(.caption2)
                Text(compact).font(.caption2).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }

    private var inlineText: String {
        guard let balance else { return "My Wallet" }
        return "Balance \(balance.total.complicationCompact(balance.currencyCode))"
    }

    private var compact: String {
        guard let balance else { return "—" }
        return balance.total.complicationCompact(balance.currencyCode)
    }
}

/// Today's spending on the watch face.
struct WatchSpendingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WalletWatchSpending", provider: WatchComplicationProvider()) { entry in
            WatchSpendingComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Spent Today")
        .description("What you have spent so far today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchSpendingComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WalletEntry

    private var currency: String { entry.snapshot?.month?.currencyCode ?? "USD" }
    private var spent: Decimal { entry.snapshot?.todaySpend ?? 0 }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Spent \(spent.complicationCompact(currency))")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Spent today").font(.caption2).foregroundStyle(.secondary)
                Text(spent.complicationCompact(currency))
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 0) {
                Image(systemName: "arrow.up.right").font(.caption2)
                Text(spent.complicationCompact(currency))
                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.5)
            }
        }
    }
}

extension Decimal {
    /// Watch faces are small; compact notation keeps the figure readable.
    func complicationCompact(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).notation(.compactName).precision(.fractionLength(0...1)))
    }
}

@main
struct WalletWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchBalanceComplication()
        WatchSpendingComplication()
    }
}
