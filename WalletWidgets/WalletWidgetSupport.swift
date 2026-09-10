import SwiftUI
import WalletDomain
import WidgetKit

/// The timeline entry every My Wallet widget renders.
///
/// The snapshot is read from the shared App Group container the app writes to; the extension never
/// opens the wallet's SwiftData store.
struct WalletEntry: TimelineEntry {
    let date: Date
    let snapshot: WalletSnapshot?

    var isPlaceholder = false
}

/// Supplies entries by reading the shared snapshot.
///
/// The app reloads timelines whenever its data changes, so the schedule here is only a safety net
/// for the case where the app has not run for a while — hourly is enough for balances and budgets.
struct WalletProvider: TimelineProvider {
    func placeholder(in context: Context) -> WalletEntry {
        WalletEntry(date: Date(), snapshot: .preview, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WalletEntry) -> Void) {
        // The widget gallery previews with sample data so the shape is visible before setup.
        let snapshot = context.isPreview ? WalletSnapshot.preview : WalletSnapshotStore.read()
        completion(WalletEntry(date: Date(), snapshot: snapshot, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WalletEntry>) -> Void) {
        let entry = WalletEntry(date: Date(), snapshot: WalletSnapshotStore.read())
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Shared presentation

extension WalletSnapshot.Entry {
    var tint: Color {
        guard let colorValue else { return kind.widgetTint }
        return Color(.sRGB,
                     red: Double((colorValue >> 16) & 0xFF) / 255,
                     green: Double((colorValue >> 8) & 0xFF) / 255,
                     blue: Double(colorValue & 0xFF) / 255,
                     opacity: 1)
    }
}

extension RecordKind {
    var widgetTint: Color {
        switch self {
        case .expense: .red
        case .income: .green
        case .transfer: .blue
        }
    }

    var widgetSymbol: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }

    /// Presentation only; the sign is never folded into the stored amount.
    var widgetSign: String {
        switch self {
        case .expense: "−"
        case .income: "+"
        case .transfer: ""
        }
    }
}

extension Decimal {
    func widgetFormatted(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).precision(.fractionLength(0...2)))
    }

    /// Compact form for tight widget families, e.g. "$12.5K".
    func widgetCompact(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).notation(.compactName).precision(.fractionLength(0...1)))
    }
}

/// The small leading icon tile, mirroring the app's 36-point row tile at widget scale.
struct WidgetIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Shown when the app has not written a snapshot yet, or after a data reset.
struct WidgetEmptyState: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "wallet.bifold")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
