import Foundation
import Testing
import WalletDomain

struct CategoryColorTests {
    @Test func starterCategoriesHaveDistinctStableColors() {
        let roots = CategorySeeds.categories.filter { $0.parentID == nil }
        #expect(roots.map(\.colorToken.hex) == ["#05B231", "#009EDB", "#D47A05", "#964B2C", "#A834FF", "#FE2826", "#5555FF", "#09AB99", "#D40363", "#B29000"])
        #expect(Set(roots.map(\.colorToken)).count == 10)
        for category in CategorySeeds.categories {
            let changed = WalletCategory(id: category.id, parentID: category.parentID, name: "Renamed", nature: .want, sortOrder: 999)
            #expect(changed.colorToken == category.colorToken)
            if let parent = roots.first(where: { $0.id == category.parentID }) {
                #expect(category.colorToken == parent.colorToken)
            }
        }
    }

    @Test func customColorsAreDeterministicAndChildrenShareTheirRootColor() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let root = WalletCategory(id: id, name: "Pets", nature: .need)
        let reconstructed = WalletCategory(id: id, name: "Animals", nature: .must)
        let child = WalletCategory(parentID: id, name: "Vet", nature: .want)
        #expect(root.colorToken == reconstructed.colorToken)
        #expect(root.colorToken == child.colorToken)
        let food = CategorySeeds.categories.first { $0.name == "Food & Drinks" }!
        #expect(WalletCategory(parentID: food.id, name: "Custom Child").colorToken == .food)
    }
}
