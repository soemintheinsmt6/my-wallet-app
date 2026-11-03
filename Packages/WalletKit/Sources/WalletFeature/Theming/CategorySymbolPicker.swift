import SwiftUI
import WalletDomain

/// Lets the user pick a different SF Symbol for a category.
///
/// The choice is saved on the category, so it syncs through iCloud like a rename. The seeded symbol
/// stays the fallback, so clearing a choice returns the category to the icon it shipped with rather
/// than to a blank tile.
struct CategorySymbolPicker: View {
    /// The category as the sheet opened; the live one from the view model is shown once loaded.
    let category: WalletCategory
    @ObservedObject var viewModel: CategoriesViewModel

    private var current: WalletCategory { viewModel.category(id: category.id) ?? category }

    var body: some View {
        WalletSymbolPicker(title: "Category Icon", name: current.name, color: current.colorToken.color,
                           current: current.symbol,
                           isCustom: current.symbolName != nil,
                           select: { symbol in Task { await viewModel.setSymbol(symbol, for: current.id) } },
                           reset: { Task { await viewModel.setSymbol(nil, for: current.id) } })
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

/// The symbols offered for categories and accounts, grouped so the grid can be browsed.
///
/// A curated list rather than every SF Symbol: the full catalog runs to thousands, most of which
/// mean nothing in a wallet, and scrolling it would be worse than useless. Every symbol must exist
/// on the oldest supported systems (iOS 17, macOS 14) or its tile renders blank there; for example
/// `wallet.bifold` and `receipt` are newer and so are left out (see `WalletSymbols` for the app's
/// own wallet icon, which falls back on older systems).
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
