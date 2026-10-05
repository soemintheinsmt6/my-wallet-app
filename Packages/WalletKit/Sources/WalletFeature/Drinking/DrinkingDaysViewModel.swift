import Combine
import Foundation
import WalletDomain

@MainActor
public final class DrinkingDaysViewModel: ObservableObject {
    @Published public private(set) var days: [DayKey: DrinkingDay] = [:]
    /// The first day of the month on screen.
    @Published public private(set) var month: DayKey
    @Published public private(set) var isLoading = true
    @Published public private(set) var isSaving = false
    @Published public var errorMessage: String?
    private let useCases: DrinkingDayUseCases
    private let now: () -> Date
    let calendar: Calendar
    private var loadVersion = 0
    private var observation: Task<Void, Never>?
    private var isReloading = false
    private var needsReload = false

    public init(useCases: DrinkingDayUseCases, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.useCases = useCases
        self.calendar = calendar
        self.now = now
        let today = DayKey(now(), calendar: calendar)
        month = DayKey(year: today.year, month: today.month, day: 1)
    }

    public var today: DayKey { DayKey(now(), calendar: calendar) }

    public var summary: DrinkingSummary {
        DrinkingSummary(days: Array(days.values), month: month, today: today, calendar: calendar)
    }

    public var canShowNextMonth: Bool {
        (month.year, month.month) < (today.year, today.month)
    }

    public func showMonth(offset: Int) {
        guard offset <= 0 || canShowNextMonth,
              let moved = calendar.date(byAdding: .month, value: offset, to: month.date(in: calendar)) else { return }
        month = DayKey(moved, calendar: calendar)
    }

    public func showCurrentMonth() {
        month = DayKey(year: today.year, month: today.month, day: 1)
    }

    /// Watched once however many screens ask — the calendar and the More screen both do.
    public func observe() async {
        if observation == nil {
            // Subscribed before the first load so a change during it is not missed.
            let changes = useCases.changes()
            observation = Task { [weak self] in
                for await _ in changes {
                    guard let self, !Task.isCancelled else { break }
                    await reload()
                }
            }
        }
        await reload()
    }

    /// Folds into the load already running rather than racing it.
    public func reload() async {
        guard !isReloading else { needsReload = true; return }
        isReloading = true
        defer { isReloading = false }
        repeat {
            needsReload = false
            await load()
        } while needsReload
    }

    private func load() async {
        loadVersion += 1
        let version = loadVersion
        isLoading = true
        defer { if version == loadVersion { isLoading = false } }
        do {
            let loaded = try await useCases.load()
            try Task.checkCancellation()
            guard version == loadVersion else { return }
            days = Dictionary(loaded.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        } catch is CancellationError {
        } catch {
            if version == loadVersion { errorMessage = error.localizedDescription }
        }
    }

    public func mark(_ day: DayKey, drinks: Int?, note: String) async throws {
        guard !isSaving else { throw DrinkingDayError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.mark(day, drinks: drinks, note: note, today: today)
        // Shown at once: while observing, the change notification's reload may already be running,
        // and the `reload()` below then folds into it and returns before it has the saved day.
        days[day] = DrinkingDay(day: day, drinks: drinks,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        await reload()
    }

    public func unmark(_ day: DayKey) async throws {
        guard !isSaving else { throw DrinkingDayError.saveInProgress }
        isSaving = true
        defer { isSaving = false }
        try await useCases.unmark(day)
        days[day] = nil
        await reload()
    }
}
