import SwiftUI
import WalletDomain

/// Lets the user pick a different SF Symbol for a category.
///
/// The seeded symbol stays the fallback, so clearing a choice returns the category to the icon it
/// shipped with rather than to a blank tile.
struct CategorySymbolPicker: View {
    let category: WalletCategory
    @ObservedObject var overrides: CategorySymbolStore

    var body: some View {
        WalletSymbolPicker(title: "Category Icon", name: category.name, color: category.colorToken.color,
                           current: overrides.symbol(for: category),
                           isCustom: overrides.hasOverride(category),
                           select: { overrides.set($0, for: category) },
                           reset: { overrides.clear(category) })
    }
}

/// Lets the user pick a different SF Symbol for an account being edited. The choice goes into the
/// editor's draft, so it is saved, and synced, with the rest of the account. Without a choice, the
/// account's type decides its icon.
struct AccountSymbolPicker: View {
    let name: String
    /// The editor's type and color, which may not be saved yet, so the preview matches the edit.
    let type: AccountType
    let color: Color
    @Binding var selection: String?

    var body: some View {
        WalletSymbolPicker(title: "Account Icon", name: name, color: color,
                           current: selection ?? type.symbol,
                           isCustom: selection != nil,
                           select: { selection = $0 },
                           reset: { selection = nil })
    }
}

/// A searchable grid of symbols under a preview of the current one, with a reset back to the
/// default. Choices apply as they are tapped; Done only closes the sheet.
struct WalletSymbolPicker: View {
    let title: String
    let name: String
    let color: Color
    let current: String
    let isCustom: Bool
    let select: (String) -> Void
    let reset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return CategorySymbolCatalog.all }
        return CategorySymbolCatalog.all.filter { $0.contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: WalletMetrics.medium) {
                        WalletIconTile(symbol: current, color: color, large: true)
                        VStack(alignment: .leading, spacing: WalletMetrics.hair) {
                            Text(name).font(.body.weight(.medium))
                            Text(isCustom ? "Custom icon" : "Default icon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: WalletMetrics.small)
                        if isCustom {
                            Button("Reset", action: reset)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    .frame(minHeight: WalletMetrics.touchTarget)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: WalletMetrics.medium)],
                              spacing: WalletMetrics.medium) {
                        ForEach(matches, id: \.self) { symbol in
                            Button { select(symbol) } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 20))
                                    .foregroundStyle(symbol == current ? .white : Color.primary)
                                    .frame(width: 48, height: 48)
                                    .background(symbol == current ? AnyShapeStyle(color)
                                                                  : AnyShapeStyle(.quaternary.opacity(0.5)),
                                                in: RoundedRectangle(cornerRadius: WalletMetrics.medium,
                                                                     style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(symbol == current ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, WalletMetrics.tight)
                } header: {
                    Text("\(matches.count) symbols")
                }
            }
            .searchable(text: $search, prompt: "Search symbols")
            .navigationTitle(title)
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }
}

/// Per-category icon choices.
///
/// Stored locally rather than on the category itself: the seeded symbols are presentation metadata
/// keyed by stable IDs, and adding a synced field would mean a schema change for a purely cosmetic
/// preference.
@MainActor
public final class CategorySymbolStore: ObservableObject {
    @Published private var overrides: [String: String]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = defaults.dictionary(forKey: WalletPreferenceKeys.categorySymbols) as? [String: String] ?? [:]
    }

    public func symbol(for category: WalletCategory) -> String {
        overrides[category.id.uuidString] ?? category.symbol
    }

    public func hasOverride(_ category: WalletCategory) -> Bool {
        overrides[category.id.uuidString] != nil
    }

    public func set(_ symbol: String, for category: WalletCategory) {
        overrides[category.id.uuidString] = symbol
        save()
    }

    public func clear(_ category: WalletCategory) {
        overrides.removeValue(forKey: category.id.uuidString)
        save()
    }

    public func clearAll() {
        overrides = [:]
        save()
    }

    private func save() {
        defaults.set(overrides, forKey: WalletPreferenceKeys.categorySymbols)
    }
}

/// The symbols offered for categories.
///
/// A curated list rather than every SF Symbol: the full catalog runs to thousands, most of which
/// mean nothing in a wallet, and scrolling it would be worse than useless.
enum CategorySymbolCatalog {
    static let all: [String] = [
        "fork.knife", "cup.and.saucer", "takeoutbag.and.cup.and.straw", "basket", "carrot",
        "birthday.cake", "wineglass", "mug",
        "bag", "cart", "tshirt", "shoe", "handbag", "gift", "sparkles", "tag",
        "house", "key", "bed.double", "sofa", "lamp.table", "shower", "washer", "hammer",
        "bolt", "flame", "drop", "wifi", "antenna.radiowaves.left.and.right",
        "car", "bus", "tram", "bicycle", "airplane", "fuelpump", "parkingsign.circle",
        "figure.walk", "scooter", "ferry",
        "heart", "cross.case", "pills", "stethoscope", "dumbbell", "figure.run", "leaf",
        "theatermasks", "film", "gamecontroller", "music.note", "ticket", "book",
        "graduationcap", "paintpalette", "camera", "sportscourt",
        "iphone", "laptopcomputer", "desktopcomputer", "keyboard", "headphones", "tv",
        "app", "icloud", "play.rectangle",
        "banknote", "creditcard", "building.columns", "percent", "chart.line.uptrend.xyaxis",
        "chart.bar", "chart.pie", "doc.text", "briefcase", "storefront", "shippingbox",
        "person", "person.2", "pawprint", "suitcase", "globe", "map", "sun.max", "umbrella",
        "wrench.and.screwdriver", "scissors", "comb", "shield", "lock", "phone", "envelope",
        "clock", "calendar", "star", "flag", "bell", "wallet.bifold", "tray.full",
    ]
}
