import Foundation
import SwiftData
import WalletDomain

extension WalletStore {
    func fetchWorkoutDays() throws -> [WorkoutDay] {
        let context = ModelContext(modelContainer)
        var newest: [DayKey: WorkoutDay] = [:]
        for day in try context.fetch(FetchDescriptor<WorkoutDayRecord>()).compactMap(\.workoutDay) {
            if let kept = newest[day.day], kept.updatedAt >= day.updatedAt { continue }
            newest[day.day] = day
        }
        return newest.values.sorted { $0.day > $1.day }
    }

    func saveWorkoutDay(_ day: WorkoutDay) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let value = day.day.rawValue
        let records = try context.fetch(FetchDescriptor<WorkoutDayRecord>(predicate: #Predicate { $0.dayValue == value }))
        if let first = records.first {
            first.apply(day)
            // Fold away copies another device uploaded for the same day.
            for extra in records.dropFirst() { context.delete(extra) }
        } else {
            context.insert(WorkoutDayRecord(day: day))
        }
        try context.save()
    }

    func deleteWorkoutDay(_ day: DayKey) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let value = day.rawValue
        // Removing an unmarked day is a no-op, so a repeat from another window is safe.
        for record in try context.fetch(FetchDescriptor<WorkoutDayRecord>(predicate: #Predicate { $0.dayValue == value })) {
            context.delete(record)
        }
        if context.hasChanges { try context.save() }
    }

    /// The list is short, so it is fetched whole and matched ignoring case in memory, which a
    /// SwiftData predicate cannot do portably.
    func fetchWorkoutExercises() throws -> [String] {
        let context = ModelContext(modelContainer)
        var seen = Set<String>()
        return try context.fetch(FetchDescriptor<WorkoutExerciseRecord>())
            .map(\.name)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func saveWorkoutExercise(_ name: String) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let key = name.lowercased()
        guard try !context.fetch(FetchDescriptor<WorkoutExerciseRecord>()).contains(where: { $0.name.lowercased() == key })
        else { return }
        context.insert(WorkoutExerciseRecord(name: name))
        try context.save()
    }

    func deleteWorkoutExercise(_ name: String) throws {
        try Task.checkCancellation()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let key = name.lowercased()
        for record in try context.fetch(FetchDescriptor<WorkoutExerciseRecord>()) where record.name.lowercased() == key {
            context.delete(record)
        }
        if context.hasChanges { try context.save() }
    }
}
