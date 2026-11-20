import SwiftUI

/// The title row above a day tracker's calendar or year chart, with arrows to page either way.
struct DayTrackerPager<Title: View>: View {
    let previousLabel: String
    let nextLabel: String
    var canShowPrevious = true
    let canShowNext: Bool
    let showPrevious: () -> Void
    let showNext: () -> Void
    @ViewBuilder let title: () -> Title

    var body: some View {
        HStack {
            Button(action: showPrevious) {
                Image(systemName: "chevron.left").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .disabled(!canShowPrevious)
            .accessibilityLabel(previousLabel)
            Spacer()
            title()
            Spacer()
            Button(action: showNext) {
                Image(systemName: "chevron.right").frame(minWidth: WalletMetrics.touchTarget, minHeight: WalletMetrics.touchTarget)
            }
            .disabled(!canShowNext)
            .accessibilityLabel(nextLabel)
        }
        .buttonStyle(.borderless)
        .textCase(nil)
    }
}

/// Two stat tiles side by side. The row keeps a small inset so its separator can sit on the
/// same leading edge as every other line on the screen; only the left tile is padded in, which
/// gives it room from the edge without moving the lines.
struct DayStatRow: View {
    let left: WalletStatTile
    let right: WalletStatTile

    init(_ left: WalletStatTile, _ right: WalletStatTile) {
        self.left = left
        self.right = right
    }

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            left.padding(.leading, WalletMetrics.medium)
            right
        }
        .listRowInsets(EdgeInsets(top: 0, leading: WalletMetrics.tight, bottom: 0, trailing: WalletMetrics.tight))
        .listRowBackground(Color.clear)
        // The row content starts at `tight`; this puts the line at the standard 16 pt margin.
        .alignmentGuide(.listRowSeparatorLeading) { _ in WalletMetrics.large - WalletMetrics.tight }
    }
}

/// "1 day" or "12 days".
func dayCountText(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }
