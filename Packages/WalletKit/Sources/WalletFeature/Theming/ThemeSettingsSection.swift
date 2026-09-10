import SwiftUI
import WalletDomain

/// Appearance customization: accent color, app icon, list density and text size.
struct ThemeSettingsSection: View {
    @ObservedObject var theme: ThemeViewModel
    /// Alternate icons declared in the app's Info.plist; empty where the platform has none.
    let iconOptions: [WalletAppIcon]

    var body: some View {
        Section {
            accentPicker

            Picker("List Density", selection: $theme.density) {
                ForEach(WalletDensity.allCases) { Text($0.title).tag($0) }
            }

            Picker("Text Size", selection: $theme.textSize) {
                ForEach(WalletTextSize.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Personalize")
        } footer: {
            Text("Text Size nudges the app relative to your system setting rather than replacing it, so Dynamic Type and accessibility sizes still apply.")
        }

        if !iconOptions.isEmpty {
            Section {
                ForEach(iconOptions) { option in
                    Button {
                        Task { await theme.setIcon(option.alternateName) }
                    } label: {
                        HStack(spacing: WalletMetrics.medium) {
                            WalletIconTile(symbol: option.symbol, color: option.color, large: true)
                            Text(option.title).foregroundStyle(.primary)
                            Spacer(minLength: WalletMetrics.small)
                            if theme.iconName == option.alternateName {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .frame(minHeight: WalletMetrics.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme.iconName == option.alternateName ? .isSelected : [])
                }
                if let message = theme.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("App Icon")
            } footer: {
                Text("Changing the icon takes effect on the Home Screen straight away.")
            }
        }
    }

    private var accentPicker: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            Text("Accent Color")
                .font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: WalletMetrics.medium)],
                      spacing: WalletMetrics.medium) {
                ForEach(WalletAccent.allCases) { accent in
                    Button { theme.accent = accent } label: {
                        VStack(spacing: WalletMetrics.tight) {
                            ZStack {
                                Circle()
                                    .fill(accent.swatch.gradient)
                                    .frame(width: 32, height: 32)
                                if theme.accent == accent {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            Text(accent.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(minWidth: 56, minHeight: WalletMetrics.touchTarget + 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Color alone never carries the choice; the name and checkmark do.
                    .accessibilityLabel(accent.title)
                    .accessibilityAddTraits(theme.accent == accent ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, WalletMetrics.tight)
    }
}

/// An app icon the user can pick.
public struct WalletAppIcon: Identifiable, Sendable, Equatable {
    /// `nil` is the icon shipped as the primary one.
    public let alternateName: String?
    public let title: String
    public let symbol: String
    public let color: Color

    public var id: String { alternateName ?? "primary" }

    public init(alternateName: String?, title: String, symbol: String, color: Color) {
        self.alternateName = alternateName
        self.title = title
        self.symbol = symbol
        self.color = color
    }
}
