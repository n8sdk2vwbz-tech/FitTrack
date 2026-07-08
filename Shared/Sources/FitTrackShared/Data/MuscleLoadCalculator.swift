import Foundation

public enum FatigueLevel: String, Codable, Hashable {
    case noData
    case fresh
    case optimal
    case elevated
    case highStrain

    public var displayName: String {
        switch self {
        case .noData: return "Keine Daten"
        case .fresh: return "Frisch"
        case .optimal: return "Optimal belastet"
        case .elevated: return "Erhöhte Belastung"
        case .highStrain: return "Hohe Belastung"
        }
    }
}

public struct MuscleLoadStatus: Identifiable {
    public let muscle: MuscleGroup
    /// Kurzfristige Belastung, exponentiell gewichteter gleitender Schnitt über ca. 3 Tage.
    public let acuteLoad: Double
    /// Langfristige Basisbelastung, exponentiell gewichteter gleitender Schnitt über ca. 28 Tage.
    public let chronicLoad: Double
    /// Acute:Chronic Workload Ratio - Verhältnis von kurz- zu langfristiger Belastung.
    public let acwr: Double
    public let fatigueLevel: FatigueLevel
    public let daysSinceLastTrained: Int?

    public init(muscle: MuscleGroup, acuteLoad: Double, chronicLoad: Double, acwr: Double, fatigueLevel: FatigueLevel, daysSinceLastTrained: Int?) {
        self.muscle = muscle
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acwr = acwr
        self.fatigueLevel = fatigueLevel
        self.daysSinceLastTrained = daysSinceLastTrained
    }

    public var id: MuscleGroup { muscle }
}

/// Leitet aus einer Historie von Belastungsimpulsen (`MuscleLoadEvent`) pro Muskel
/// eine akute/chronische Trainingslast ab (EWMA-basiertes ACWR-Modell, angelehnt an
/// den in der Sportwissenschaft gebräuchlichen Ansatz von Williams et al. 2016).
/// So lässt sich abschätzen, welche Muskeln aktuell stark beansprucht und noch nicht
/// regeneriert sind.
public enum MuscleLoadCalculator {

    private static let acuteSpanDays = 3.0
    private static let chronicSpanDays = 28.0

    public static func status(for events: [MuscleLoadEvent], asOf: Date = .now, calendar: Calendar = .current) -> [MuscleGroup: MuscleLoadStatus] {
        var result: [MuscleGroup: MuscleLoadStatus] = [:]
        let grouped = Dictionary(grouping: events, by: { $0.muscle })

        for muscle in MuscleGroup.allCases {
            let muscleEvents = grouped[muscle] ?? []
            result[muscle] = status(forSingleMuscle: muscle, events: muscleEvents, asOf: asOf, calendar: calendar)
        }
        return result
    }

    private static func status(forSingleMuscle muscle: MuscleGroup, events: [MuscleLoadEvent], asOf: Date, calendar: Calendar) -> MuscleLoadStatus {
        guard let firstDate = events.map({ calendar.startOfDay(for: $0.date) }).min() else {
            return MuscleLoadStatus(muscle: muscle, acuteLoad: 0, chronicLoad: 0, acwr: 0, fatigueLevel: .noData, daysSinceLastTrained: nil)
        }

        let today = calendar.startOfDay(for: asOf)
        var dailyVolume: [Date: Double] = [:]
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            dailyVolume[day, default: 0] += event.volume
        }

        let lambdaAcute = 2.0 / (acuteSpanDays + 1.0)
        let lambdaChronic = 2.0 / (chronicSpanDays + 1.0)

        var ewmaAcute = 0.0
        var ewmaChronic = 0.0
        var cursor = firstDate
        var lastTrainedDay: Date?

        while cursor <= today {
            let volume = dailyVolume[cursor] ?? 0
            if volume > 0 { lastTrainedDay = cursor }
            ewmaAcute = volume * lambdaAcute + ewmaAcute * (1 - lambdaAcute)
            ewmaChronic = volume * lambdaChronic + ewmaChronic * (1 - lambdaChronic)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let acwr = ewmaChronic > 0.01 ? ewmaAcute / ewmaChronic : (ewmaAcute > 0 ? 2.0 : 0)
        let daysSince = lastTrainedDay.flatMap { calendar.dateComponents([.day], from: $0, to: today).day }

        let level: FatigueLevel
        if ewmaChronic <= 0.01 && ewmaAcute <= 0.01 {
            level = .noData
        } else if acwr < 0.8 {
            level = .fresh
        } else if acwr <= 1.3 {
            level = .optimal
        } else if acwr <= 1.5 {
            level = .elevated
        } else {
            level = .highStrain
        }

        return MuscleLoadStatus(
            muscle: muscle,
            acuteLoad: ewmaAcute,
            chronicLoad: ewmaChronic,
            acwr: acwr,
            fatigueLevel: level,
            daysSinceLastTrained: daysSince
        )
    }

    /// Gesamttrainingslast über alle Muskeln, als Eingabe für die Regenerationsvorhersage.
    public static func overallLoad(from statuses: [MuscleGroup: MuscleLoadStatus]) -> (acute: Double, chronic: Double) {
        let values = statuses.values.filter { $0.fatigueLevel != .noData }
        guard !values.isEmpty else { return (0, 0) }
        let acute = values.reduce(0) { $0 + $1.acuteLoad }
        let chronic = values.reduce(0) { $0 + $1.chronicLoad }
        return (acute, chronic)
    }
}
