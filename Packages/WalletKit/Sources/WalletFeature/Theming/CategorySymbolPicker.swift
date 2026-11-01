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

    private var matches: [CategorySymbolCatalog.Group] { CategorySymbolCatalog.groups(matching: search) }

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

                ForEach(matches) { group in
                    Section(group.title) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: WalletMetrics.medium)],
                                  spacing: WalletMetrics.medium) {
                            ForEach(group.symbols, id: \.self) { symbol in
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
                    }
                }
                if matches.isEmpty {
                    Section {
                        Text("No symbols match “\(search)”.").foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search symbols or groups")
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

/// The symbols offered for categories and accounts, grouped so the grid can be browsed.
///
/// A curated list rather than every SF Symbol: the full catalog runs to thousands, most of which
/// mean nothing in a wallet, and scrolling it would be worse than useless. Every symbol must exist
/// on the oldest supported systems (iOS 17, macOS 14) or its tile renders blank there; for example
/// `wallet.bifold` and `receipt` are newer and so are left out.
enum CategorySymbolCatalog {
    struct Group: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Food & Drink", symbols: [
            "fork.knife", "cup.and.saucer", "mug", "takeoutbag.and.cup.and.straw", "wineglass",
            "waterbottle", "birthday.cake", "carrot", "fish", "frying.pan", "refrigerator", "oven",
            "popcorn", "basket",
        ]),
        Group(title: "Shopping", symbols: [
            "cart", "bag", "handbag", "backpack", "tshirt", "shoe", "eyeglasses", "hanger", "gift",
            "giftcard", "tag", "sparkles", "comb", "scissors", "shippingbox", "storefront",
        ]),
        Group(title: "Home", symbols: [
            "house", "house.lodge", "building.2", "key", "bed.double", "sofa", "chair.lounge",
            "lamp.table", "lightbulb", "shower", "bathtub", "toilet", "washer", "dryer", "spigot",
            "paintbrush", "hammer", "screwdriver", "wrench.and.screwdriver", "trash",
            "heater.vertical", "air.conditioner.horizontal",
        ]),
        Group(title: "Bills & Utilities", symbols: [
            "bolt", "flame", "drop", "wifi", "antenna.radiowaves.left.and.right", "phone",
            "envelope", "powerplug", "tv",
        ]),
        Group(title: "Transport", symbols: [
            "car", "car.2", "bus", "tram", "train.side.front.car", "bicycle", "scooter",
            "airplane", "ferry", "sailboat", "fuelpump", "ev.charger", "bolt.car",
            "parkingsign.circle", "steeringwheel", "road.lanes", "figure.walk",
        ]),
        Group(title: "Health & Fitness", symbols: [
            "heart", "cross.case", "cross", "cross.vial", "pills", "syringe", "bandage",
            "stethoscope", "brain.head.profile", "lungs", "dumbbell", "figure.run", "figure.yoga",
            "figure.pool.swim", "figure.skiing.downhill", "tennis.racket", "soccerball",
            "basketball", "leaf",
        ]),
        Group(title: "Fun & Learning", symbols: [
            "theatermasks", "film", "gamecontroller", "music.note", "guitars", "headphones",
            "ticket", "book", "books.vertical", "newspaper", "graduationcap", "pencil",
            "paintpalette", "camera", "photo", "puzzlepiece", "dice", "sportscourt",
            "party.popper", "balloon", "crown",
        ]),
        Group(title: "Tech", symbols: [
            "iphone", "ipad", "laptopcomputer", "desktopcomputer", "keyboard", "printer",
            "applewatch", "app", "icloud", "play.rectangle", "server.rack", "externaldrive", "cpu",
            "network",
        ]),
        Group(title: "Money", symbols: [
            "banknote", "creditcard", "creditcard.and.123", "wallet.pass", "dollarsign.circle",
            "eurosign.circle", "sterlingsign.circle", "yensign.circle", "indianrupeesign.circle",
            "bitcoinsign.circle", "building.columns", "percent", "chart.line.uptrend.xyaxis",
            "chart.line.downtrend.xyaxis", "chart.bar", "chart.pie", "arrow.left.arrow.right",
            "doc.text", "signature", "briefcase", "case", "scalemass", "lock.shield",
        ]),
        Group(title: "People & Pets", symbols: [
            "person", "person.2", "person.3", "figure.2.and.child.holdinghands", "stroller",
            "teddybear", "hand.raised", "pawprint", "dog", "cat", "bird", "hare",
        ]),
        Group(title: "Travel", symbols: [
            "suitcase", "suitcase.rolling", "globe", "map", "mappin.and.ellipse", "tent",
            "mountain.2", "beach.umbrella", "sun.max", "umbrella",
        ]),
        Group(title: "Other", symbols: [
            "clock", "calendar", "star", "flag", "bell", "tray.full", "folder", "archivebox",
            "lock", "shield", "questionmark.circle", "ellipsis.circle",
        ]),
    ]

    static var all: [String] { groups.flatMap(\.symbols) }

    /// The groups narrowed to a search, which matches symbol names (`car` finds `car.2`) and
    /// group titles (`travel` finds the whole Travel group). Empty groups are dropped.
    static func groups(matching search: String) -> [Group] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.title.lowercased().contains(query) { return group }
            let symbols = group.symbols.filter { $0.contains(query) }
            return symbols.isEmpty ? nil : Group(title: group.title, symbols: symbols)
        }
    }
}
