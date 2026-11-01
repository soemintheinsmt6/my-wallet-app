import Testing
@testable import WalletFeature
#if os(macOS)
import AppKit
#endif

struct SymbolCatalogTests {
    @Test func everyOfferedSymbolExistsAndAppearsOnce() {
        let all = CategorySymbolCatalog.all
        #expect(all.count > 150)
        #expect(Set(all).count == all.count)
        #if os(macOS)
        for symbol in all {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
        #endif
    }

    @Test func searchMatchesSymbolNamesAndGroupTitles() {
        let cars = CategorySymbolCatalog.groups(matching: " car ")
        #expect(cars.flatMap(\.symbols).contains("car.2"))
        #expect(cars.allSatisfy { group in group.symbols.allSatisfy { $0.contains("car") } })

        let travel = CategorySymbolCatalog.groups(matching: "Travel")
        #expect(travel.map(\.title) == ["Travel"])
        #expect(travel.first?.symbols == CategorySymbolCatalog.groups.first { $0.title == "Travel" }?.symbols)

        #expect(CategorySymbolCatalog.groups(matching: "zzz").isEmpty)
        #expect(CategorySymbolCatalog.groups(matching: "").count == CategorySymbolCatalog.groups.count)
    }
}
