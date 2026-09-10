import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchBillReminders() throws -> [BillReminder] {
        let context = ModelContext(modelContainer)
        return try context.fetch(FetchDescriptor<BillReminderRecord>()).map { try $0.value }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    func saveBillReminder(_ bill: BillReminder) throws {
        try bill.validate()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        if let id = bill.accountID {
            guard let account = try context.fetch(FetchDescriptor<AccountRecord>(predicate: #Predicate { $0.id == id })).first,
                  account.currencyCode == bill.currencyCode else { throw PlanningError.missingItem }
        }
        if let id = bill.categoryID {
            guard canonicalCategories(try context.fetch(FetchDescriptor<CategoryRecord>())).contains(where: { $0.id == id }) else { throw PlanningError.missingItem }
        }
        let id = bill.id
        let records = try context.fetch(FetchDescriptor<BillReminderRecord>(predicate: #Predicate { $0.id == id }))
        if records.isEmpty { context.insert(try BillReminderRecord(bill)) }
        else {
            for record in records {
                var updated = bill
                let old = try record.value
                updated.nextIndex = old.nextIndex
                updated.isPaid = old.isPaid
                if old.nextIndex > 0 { updated.dueDate = old.dueDate }
                try record.apply(updated)
            }
        }
        try context.save()
    }

    func deleteBillReminder(id: UUID) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        for bill in try context.fetch(FetchDescriptor<BillReminderRecord>(predicate: #Predicate { $0.id == id })) { context.delete(bill) }
        try context.save()
    }

    func markBillPaid(id: UUID, occurrenceIndex: Int, createRecord: Bool, paidAt: Date) throws {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<BillReminderRecord>(predicate: #Predicate { $0.id == id }))
        guard let model = records.first else { throw PlanningError.missingItem }
        var bill = try model.value
        guard !bill.isPaid, bill.nextIndex == occurrenceIndex else { return }
        guard bill.nextDueDate != nil else { throw PlanningError.completedOccurrence }
        if createRecord {
            var draft = RecordDraft()
            draft.kind = .expense
            draft.accountID = bill.accountID
            draft.categoryID = bill.categoryID
            draft.amount = bill.amount
            draft.date = paidAt
            draft.payee = bill.name
            draft.note = "Bill payment: \(bill.name)"
            let recordID = ScheduledOccurrence.identifier(owner: id, index: occurrenceIndex, kind: "bill")
            try writeRecord(id: recordID, draft: draft, in: context)
        }
        bill.nextIndex += 1
        if bill.recurrence == nil || bill.recurrence?.date(start: bill.dueDate, index: bill.nextIndex) == nil { bill.isPaid = true }
        for record in records { try record.apply(bill) }
        try context.save()
    }
}
