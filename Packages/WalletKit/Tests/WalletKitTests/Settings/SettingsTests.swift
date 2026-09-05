import Foundation
import SwiftUI
import Testing
import WalletDomain
@testable import WalletData
@testable import WalletFeature

@MainActor
struct SettingsTests {
    @Test func resetDeletesWalletDataAndReseedsOnlyStarterCategories() async throws {
        let repository = try await SwiftDataWalletRepository.make(configuration: .inMemory)
        let account = Account(name: "Reset test", type: .cash)
        try await repository.createAccount(account)
        let category = try #require(try await repository.fetchCategories().first)
        try await repository.createCategory(name: "Custom", nature: .want, parentID: nil)
        try await repository.createTag(name: "Test", color: .blue)
        let tag = try #require(try await repository.fetchTags().first)
        try await repository.add(WalletEntry(timestamp: Date()))
        var draft = RecordDraft()
        draft.accountID = account.id
        draft.categoryID = category.id
        draft.amount = 10
        draft.tagIDs = [tag.id]
        draft.photoData = Data([1, 2, 3])
        let id = UUID()
        try await repository.createRecord(id: id, draft: draft)
        var changes = repository.changes().makeAsyncIterator()
        try await ResetWalletUseCase(repository: repository).execute()
        let change: Void? = await changes.next()
        #expect(change != nil)
        #expect(try await repository.fetchAccounts().isEmpty)
        #expect(try await repository.fetchRecords().isEmpty)
        #expect(try await repository.fetchTags().isEmpty)
        #expect(try await repository.fetchEntries().isEmpty)
        #expect(try await repository.recordPhoto(id: id) == nil)
        let categories = try await repository.fetchCategories()
        #expect(categories.count == 60)
        #expect(!categories.contains { $0.name == "Custom" })
        try await repository.resetWalletData()
        #expect(try await repository.fetchAccounts().isEmpty)
    }

    @Test func successfulResetClearsRecordDefaultsButKeepsTheme() async throws {
        let suite = "wallet-settings-test-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("dark", forKey: WalletPreferenceKeys.appearance)
        preferences.set(UUID().uuidString, forKey: WalletPreferenceKeys.lastUsedAccountID)
        preferences.set("cash", forKey: WalletPreferenceKeys.lastUsedPaymentType)
        let repository = ResetStub()
        let model = SettingsViewModel(resetUseCase: ResetWalletUseCase(repository: repository), preferences: preferences)
        await model.resetData()
        #expect(repository.calls == 1)
        #expect(model.resetGeneration == 1)
        #expect(!model.isResetting)
        #expect(model.errorMessage == nil)
        #expect(preferences.string(forKey: WalletPreferenceKeys.appearance) == "dark")
        #expect(preferences.object(forKey: WalletPreferenceKeys.lastUsedAccountID) == nil)
        #expect(preferences.object(forKey: WalletPreferenceKeys.lastUsedPaymentType) == nil)
    }

    @Test func resetFailurePreservesPreferencesAndNavigation() async throws {
        let suite = "wallet-settings-test-\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("keep", forKey: WalletPreferenceKeys.lastUsedAccountID)
        let repository = ResetStub()
        repository.fails = true
        let model = SettingsViewModel(resetUseCase: ResetWalletUseCase(repository: repository), preferences: preferences)
        await model.resetData()
        #expect(model.errorMessage != nil)
        #expect(!model.isResetting)
        #expect(model.resetGeneration == 0)
        #expect(preferences.string(forKey: WalletPreferenceKeys.lastUsedAccountID) == "keep")
    }

    @Test func appearanceMapsSystemToNoOverride() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppAppearance.allCases.count == 3)
    }
}

@MainActor
private final class ResetStub: WalletResetRepository {
    var calls = 0
    var fails = false
    func resetWalletData() async throws {
        calls += 1
        if fails { throw CocoaError(.fileWriteUnknown) }
    }
}
