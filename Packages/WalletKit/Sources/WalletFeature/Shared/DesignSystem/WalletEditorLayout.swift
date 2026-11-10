import SwiftUI

// The pieces of the record editor's layout, shared so every editor built on it reads the same:
// an amount at the top, then uppercase section headings over rows of gray symbols
// (`RecordFormRow`), with text and choices pushed as their own screens.

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

/// Explanation under a group of rows, standing in for a form section's footer.
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
