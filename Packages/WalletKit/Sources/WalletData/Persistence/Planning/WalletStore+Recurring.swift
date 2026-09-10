import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchRecurringSeries() throws -> [RecurringSeries] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<RecurringSeriesRecord>()).map { try $0.value }
            .sorted { ($0.nextDate ?? .distantFuture) < ($1.nextDate ?? .distantFuture) }
    }

    func fetchOccurrences() throws -> [ScheduledOccurrence] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<ScheduledOccurrenceRecord>()).map { try $0.value }
    }

    func updateRecurringSeries(_ series: RecurringSeries) throws {
        try series.rule.validate(start: series.startDate)
        try series.template.validate()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let id = series.id
        let models = try context.fetch(FetchDescriptor<RecurringSeriesRecord>(predicate: #Predicate { $0.id == id }))
        guard !models.isEmpty else { throw PlanningError.missingItem }
        for model in models {
            let old = try model.value
            // Edits cannot rewind the cursor or move the original anchor and replay paid records.
            var updated = series
            updated.nextIndex = old.nextIndex
            updated.startDate = old.startDate
            updated.template.recurrence = nil
            try model.apply(updated)
        }
        try context.save()
    }

    func saveOccurrence(_ occurrence: ScheduledOccurrence) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let seriesID = occurrence.seriesID
        guard let model = try context.fetch(FetchDescriptor<RecurringSeriesRecord>(predicate: #Predicate { $0.id == seriesID })).first else {
            throw PlanningError.missingItem
        }
        let series = try model.value
        let id = occurrence.id
        let models = try context.fetch(FetchDescriptor<ScheduledOccurrenceRecord>(predicate: #Predicate { $0.id == id }))
        let deferred = try models.first?.value
        guard (occurrence.index >= series.nextIndex || deferred?.completed == false), series.rule.date(start: series.startDate, index: occurrence.index) != nil else {
            throw PlanningError.completedOccurrence
        }
        if let draft = occurrence.overrideDraft { try draft.validate() }
        var value = occurrence
        value.completed = false
        if models.isEmpty { context.insert(try ScheduledOccurrenceRecord(value)) }
        else {
            for model in models {
                guard try !model.value.completed else { throw PlanningError.completedOccurrence }
                try model.apply(value)
            }
        }
        try context.save()
    }

    /// One context save advances cursors, writes occurrence receipts and applies all ledger effects.
    /// Receipts remain after record deletion, so catch-up never recreates a deleted occurrence.
    func generateDueRecords(through date: Date) throws -> Int {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var generated = 0
        for model in try context.fetch(FetchDescriptor<RecurringSeriesRecord>()) {
            var series = try model.value
            guard series.state == .active else { continue }
            var processed = 0
            // Modified dates may fall before or after the regular cadence. Process them
            // independently so a postponed occurrence never blocks later regular records.
            for receipt in try context.fetch(FetchDescriptor<ScheduledOccurrenceRecord>()) {
                var occurrence = try receipt.value
                guard occurrence.seriesID == series.id, !occurrence.completed, !occurrence.skipped,
                      var draft = occurrence.overrideDraft, draft.date <= date, processed < 500 else { continue }
                draft.recurrence = nil
                try writeRecord(id: occurrence.id, draft: draft, in: context)
                occurrence.completed = true
                try receipt.apply(occurrence)
                generated += 1
                processed += 1
            }
            while let due = series.nextDate, due <= date, processed < 500 {
                try Task.checkCancellation()
                let id = ScheduledOccurrence.identifier(owner: series.id, index: series.nextIndex, kind: "recurring")
                let receipts = try context.fetch(FetchDescriptor<ScheduledOccurrenceRecord>(predicate: #Predicate { $0.id == id }))
                var occurrence = try receipts.first?.value ?? ScheduledOccurrence(seriesID: series.id, index: series.nextIndex)
                let effectiveDate = occurrence.overrideDraft?.date ?? due
                if !occurrence.skipped && !occurrence.completed && effectiveDate <= date {
                    var draft = occurrence.overrideDraft ?? series.template
                    if occurrence.overrideDraft == nil { draft.date = due }
                    draft.recurrence = nil
                    try writeRecord(id: id, draft: draft, in: context)
                    generated += 1
                    occurrence.completed = true
                }
                if occurrence.skipped { occurrence.completed = true }
                if receipts.isEmpty { context.insert(try ScheduledOccurrenceRecord(occurrence)) }
                else { for receipt in receipts { try receipt.apply(occurrence) } }
                series.nextIndex += 1
                processed += 1
            }
            try model.apply(series)
        }
        if context.hasChanges { try context.save() }
        return generated
    }
}
