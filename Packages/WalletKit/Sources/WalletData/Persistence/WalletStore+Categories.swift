import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchCategories() throws -> [WalletCategory] {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var records = try context.fetch(FetchDescriptor<CategoryRecord>())
        let existingIDs = Set(records.map(\.id))
        let defaults = Dictionary(uniqueKeysWithValues: CategorySeeds.categories.map { ($0.id, $0.nature) })
        // Upgrade untouched earlier seeds. A user save always has a non-epoch timestamp,
        // including an explicit choice of None, so it is never replaced by defaults.
        for record in records where record.updatedAt == Date(timeIntervalSince1970: 0) && record.natureValue == CategoryNature.none.rawValue {
            if let nature = defaults[record.id], nature != .none {
                record.natureValue = nature.rawValue
            }
        }
        for category in CategorySeeds.categories where !existingIDs.contains(category.id) {
            let record = CategoryRecord(category: category, updatedAt: Date(timeIntervalSince1970: 0))
            context.insert(record)
            records.append(record)
        }
        if context.hasChanges { try context.save() }
        return canonicalCategories(records)
    }

    func createCategory(name: String, nature: CategoryNature, parentID: UUID?) throws {
        try Task.checkCancellation()
        _ = try fetchCategories()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let categories = canonicalCategories(try context.fetch(FetchDescriptor<CategoryRecord>()))
        if let parentID {
            guard categories.contains(where: { $0.id == parentID && $0.parentID == nil }) else {
                throw CategoryValidationError.invalidParent
            }
        }
        try validateCategoryName(name, parentID: parentID, excluding: nil, categories: categories)
        let nextOrder = (categories.filter { $0.parentID == parentID }.map(\.sortOrder).max() ?? -1) + 1
        context.insert(CategoryRecord(category: WalletCategory(parentID: parentID, name: name, nature: nature, sortOrder: nextOrder)))
        try context.save()
    }

    func updateCategory(id: UUID, name: String, nature: CategoryNature) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<CategoryRecord>())
        let categories = canonicalCategories(records)
        guard let existing = categories.first(where: { $0.id == id }) else { throw CategoryValidationError.notFound }
        try validateCategoryName(name, parentID: existing.parentID, excluding: id, categories: categories)
        let now = Date()
        for record in records where record.id == id {
            record.name = name
            record.natureValue = nature.rawValue
            record.updatedAt = now
        }
        try context.save()
    }

    /// Writes every replica of the category with a fresh timestamp, as a rename does, so the
    /// choice wins over older copies on other devices and syncs as an ordinary edit.
    func setCategorySymbol(id: UUID, symbolName: String?) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<CategoryRecord>())
        guard canonicalCategories(records).contains(where: { $0.id == id }) else {
            throw CategoryValidationError.notFound
        }
        let now = Date()
        for record in records where record.id == id {
            record.symbolName = symbolName
            record.updatedAt = now
        }
        try context.save()
    }

    func deleteCategory(id: UUID, strategy: CategoryDeletionStrategy) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<CategoryRecord>())
        let categories = canonicalCategories(records)
        guard categories.contains(where: { $0.id == id }) else { return }
        let children = categories.filter { $0.parentID == id }
        var deletedIDs: Set<UUID> = [id]
        var destinationID: UUID?
        switch strategy {
        case .deleteSubcategories:
            deletedIDs.formUnion(children.map(\.id))
        case .reassignSubcategories(let destination):
            guard destination != id, categories.contains(where: { $0.id == destination && $0.parentID == nil }) else {
                throw CategoryValidationError.invalidParent
            }
            for child in children {
                try validateCategoryName(child.name, parentID: destination, excluding: child.id, categories: categories)
            }
            destinationID = destination
        }
        guard categories.contains(where: { !deletedIDs.contains($0.id) }) else { throw CategoryValidationError.lastCategory }
        let childIDs = Set(children.map(\.id))
        let now = Date()
        for record in records {
            if deletedIDs.contains(record.id) {
                // Keep a tombstone so default seeding and older offline replicas cannot resurrect it.
                record.deletionDate = now
                record.updatedAt = now
            } else if childIDs.contains(record.id), let destinationID {
                record.parentID = destinationID
                record.updatedAt = now
            }
        }
        for record in try context.fetch(FetchDescriptor<TransactionRecord>()) {
            if let categoryID = record.categoryID, deletedIDs.contains(categoryID) { record.categoryID = nil }
        }
        try context.save()
    }

    /// Deterministically hide duplicate logical seed IDs without deleting synced records.
    /// Seed timestamps are the epoch, so imported seed defaults never replace an edit.
    func canonicalCategories(_ records: [CategoryRecord]) -> [WalletCategory] {
        let sorted = records.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.replicaID.uuidString < $1.replicaID.uuidString
        }
        var seen = Set<UUID>()
        return sorted.filter { seen.insert($0.id).inserted }.filter { $0.deletionDate == nil }.map(\.category).sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func validateCategoryName(_ name: String, parentID: UUID?, excluding id: UUID?, categories: [WalletCategory]) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 80 else { throw CategoryValidationError.invalidName }
        let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        guard !categories.contains(where: {
            $0.id != id && $0.parentID == parentID &&
                $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) == key
        }) else { throw CategoryValidationError.duplicateName }
    }
}
