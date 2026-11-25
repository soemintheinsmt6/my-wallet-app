import Foundation

/// Whether a spending category is about alcohol, judged from its name, so the record editor can
/// suggest marking the day as a drinking day.
///
/// Names are compared word by word, ignoring case and accents, so "Gin" matches but "Engine" does
/// not. "Bar" counts, so the starter "Bar & Café" category offers the switch on coffee too; it
/// stays off unless turned on, so a coffee costs only a glance.
public enum AlcoholCategories {
    static let words: Set<String> = [
        "alcohol", "alcoholic", "booze", "liquor", "liquors", "spirits", "bar", "bars",
        "beer", "beers", "ale", "lager", "cider", "brewery", "pub", "pubs",
        "wine", "wines", "winery", "champagne", "prosecco", "sake", "soju", "makgeolli", "shochu",
        "whiskey", "whiskeys", "whisky", "whiskies", "bourbon", "scotch", "brandy", "cognac",
        "vodka", "gin", "rum", "tequila", "mezcal", "baijiu",
        "cocktail", "cocktails", "nightlife", "nightclub", "club", "clubs", "clubbing",
    ]

    /// Whether the category or, for a subcategory, its parent is named after alcohol.
    public static func contains(_ category: WalletCategory?, in categories: [WalletCategory]) -> Bool {
        guard let category else { return false }
        if isAlcohol(category.name) { return true }
        guard let parentID = category.parentID else { return false }
        return categories.first { $0.id == parentID }.map { isAlcohol($0.name) } ?? false
    }

    public static func isAlcohol(_ name: String) -> Bool {
        PayeeSuggestions.fold(name)
            .split { !$0.isLetter }
            .contains { words.contains(String($0)) }
    }
}
