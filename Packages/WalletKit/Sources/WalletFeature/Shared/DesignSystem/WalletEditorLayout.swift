import SwiftUI

// The pieces of the record editor's layout, shared so every editor built on it reads the same:
// an amount at the top, then uppercase section headings over rows of gray symbols
// (`RecordFormRow`), with text and choices pushed as their own screens.

extension View {
    /// On an editor's stack of rows: white behind them, so the rows stay white on the page's band.
    func walletEditorRows() -> some View {
        background(.background)
    }

    /// On an editor's `ScrollView`: the page beyond its rows takes the headings' band, so a page
    /// that ends before the screen does carries the band to the bottom, as a grouped form's
    /// background does, instead of stopping in white.
    func walletEditorPage() -> some View {
        background {
            Rectangle().fill(.background)
                .overlay(Rectangle().fill(.quaternary.opacity(0.35)))
                .ignoresSafeArea()
        }
    }
}

/// An uppercase heading on a tinted band, opening a group of editor rows.
struct WalletEditorSectionHeader: View {
    let title: String
    /// Tapping the band puts the keyboard away, as tapping anywhere outside a field does.
    var onTap: () -> Void = {}

    var body: some View {
        Text(title.uppercased())
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .background(.quaternary.opacity(0.35))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The editor's section heading as a row of a plain `List`, for detail screens that need a list's
/// swipe actions and pull to refresh but should read like the editors. Placed among the rows rather
/// than as a section header, because a plain list pads above every header: the gap under a group's
/// last row would then be larger than the gap above its first. Full width and without rules; the
/// row above it hides its bottom rule, since the band separates the groups.
struct WalletListSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        WalletEditorSectionHeader(title: title)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A list row's leading tile, title and trailing value, as the editors lay out a row.
struct WalletListValueRow<Tile: View>: View {
    let title: String
    let value: String
    @ViewBuilder let tile: Tile

    var body: some View {
        HStack(spacing: WalletMetrics.medium) {
            tile
            Text(title)
            Spacer(minLength: WalletMetrics.small)
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .walletListRowPadding(0)
        .accessibilityElement(children: .combine)
    }
}

/// The right chevron of a row that pushes a screen.
struct WalletEditorChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }
}

/// A row's title, its current value in secondary text, and a chevron; tapping opens a screen.
struct WalletEditorNavigationButton: View {
    let title: String
    let value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary).lineLimit(1) }
                WalletEditorChevron()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Explanation under a group of rows, standing in for a form section's footer. It sits on the
/// section headers' tinted band, outside the white rows, so it reads as a note about them rather
/// than as another row; followed by a header, the two make one band.
struct WalletEditorCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WalletMetrics.xLarge)
            .padding(.vertical, WalletMetrics.medium)
            // The same band as `WalletEditorSectionHeader`.
            .background(.quaternary.opacity(0.35))
    }
}

/// The full-width Save pinned under an editor's rows, above the keyboard. Attach with
/// `.safeAreaInset(edge: .bottom, spacing: 0)`.
struct WalletEditorBottomButton: View {
    let title: String
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Button(action: action) {
                HStack {
                    Spacer()
                    if isBusy { ProgressView() } else { Text(title).font(.headline) }
                    Spacer()
                }
                .frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            // A pill matches the segmented type control and currency chip above it, and the
            // capsule controls of current iOS.
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!isEnabled)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.background)
    }
}

/// The last row of an editor for something already saved, laid out as a row so its icon and
/// title line up with the rows above.
struct WalletEditorDeleteButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            RecordFormRow(symbol: "trash", color: .red, showsDivider: false) {
                Text(title).foregroundStyle(.red)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
