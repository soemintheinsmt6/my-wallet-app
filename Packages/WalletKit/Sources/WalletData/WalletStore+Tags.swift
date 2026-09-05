import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchTags() throws -> [WalletTag] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<TagRecord>()).map(\.tag).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func createTag(name: String, color: TagColor) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<TagRecord>())
        let name = try validateTagName(name, excluding: nil, records: records)
        context.insert(TagRecord(tag: WalletTag(name: name, color: color)))
        try context.save()
    }

    func updateTag(id: UUID, name: String, color: TagColor) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<TagRecord>())
        guard records.contains(where: { $0.id == id }) else { throw TagValidationError.notFound }
        let name = try validateTagName(name, excluding: id, records: records)
        for record in records where record.id == id {
            record.name = name
            record.colorValue = color.rawValue
        }
        try context.save()
    }

    func deleteTag(id: UUID) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<TagRecord>(predicate: #Predicate { $0.id == id }))
        // Repeated deletion is safe if another window/device already removed the label.
        for record in records { context.delete(record) }
        if context.hasChanges { try context.save() }
    }

    private func validateTagName(_ name: String, excluding id: UUID?, records: [TagRecord]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw TagValidationError.invalidName }
        let locale = Locale(identifier: "en_US_POSIX")
        let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        guard !records.contains(where: {
            $0.id != id && $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == key
        }) else { throw TagValidationError.duplicateName }
        return trimmed
    }
}
