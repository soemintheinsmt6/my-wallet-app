import WalletDomain

extension WorkoutActivity {
    var title: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .cycle: "Cycle"
        case .swim: "Swim"
        case .gym: "Gym"
        case .home: "Home"
        case .yoga: "Yoga"
        case .sport: "Sport"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .gym: "dumbbell"
        case .home: "figure.strengthtraining.functional"
        case .yoga: "figure.yoga"
        case .sport: "sportscourt"
        case .other: WorkoutActivity.unspecifiedSymbol
        }
    }

    /// For a workout day with no activity chosen.
    static let unspecifiedSymbol = "figure.mixed.cardio"
}

extension WorkoutDay {
    var symbol: String { activity?.symbol ?? WorkoutActivity.unspecifiedSymbol }
}

/// "45 min", "1 hr" or "1 hr 30 min".
func workoutDurationText(minutes: Int) -> String {
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return "\(rest) min" }
    return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
}
