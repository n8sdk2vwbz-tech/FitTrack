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

/// Kurzfristige Antwort auf "kann ich diesen Muskel HEUTE wieder trainieren"
/// (siehe `MuscleLoadStatus.shortTermReadiness`) - bewusst als eigener Typ,
/// getrennt von `FatigueLevel`/ACWR (das nur die längerfristige Trainings-
/// konsistenz über Wochen bewertet und direkt nach einer harten Einheit
/// fälschlich "optimal" anzeigen kann, obwohl der Muskel akut noch nicht
/// erholt ist).
public enum ShortTermReadiness: Hashable {
    case noData
    case recovering(hoursRemaining: Double)
    case ready
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
    /// Exakter Zeitpunkt der letzten Belastung (nicht auf den Kalendertag
    /// gerundet wie `daysSinceLastTrained`) - Grundlage für den kurzfristigen
    /// Erholungsstatus (siehe `recoveryHoursRemaining`), der z.B. "vor 3 Std.
    /// trainiert" von einem tage-alten `daysSinceLastTrained == 0` unterscheiden
    /// kann.
    public let lastTrainedDate: Date?
    /// `true`, wenn sich die langfristige (28-Tage-)Basis in den letzten
    /// `rampingUpLookbackDays` Tagen deutlich verändert hat (siehe
    /// `MuscleLoadCalculator`) - egal ob durch Wiedereinstieg nach
    /// ruhigerer Zeit ODER durch erstmaligen Aufbau einer bisher kaum
    /// trainierten Muskelgruppe. In beiden Fällen kommt ein hohes
    /// ACWR-Verhältnis eher durch einen gerade erst im Umbruch befindlichen
    /// Nenner zustande als durch eine bereits stabile hohe Basis, auf die
    /// noch mehr draufkommt. Für die UI wichtig, damit "Hohe Belastung"
    /// nicht fälschlich wie eine Übertrainings-Warnung wirkt, obwohl gerade
    /// erst wieder/zum ersten Mal gesteigert wird.
    public let isRampingUp: Bool

    public init(muscle: MuscleGroup, acuteLoad: Double, chronicLoad: Double, acwr: Double, fatigueLevel: FatigueLevel, daysSinceLastTrained: Int?, lastTrainedDate: Date? = nil, isRampingUp: Bool = false) {
        self.muscle = muscle
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acwr = acwr
        self.fatigueLevel = fatigueLevel
        self.daysSinceLastTrained = daysSinceLastTrained
        self.lastTrainedDate = lastTrainedDate
        self.isRampingUp = isRampingUp
    }

    public var id: MuscleGroup { muscle }

    /// Stunden seit der letzten Belastung dieses Muskels - `nil` ohne
    /// bekannten Zeitpunkt (siehe `lastTrainedDate`).
    public func hoursSinceLastTrained(asOf: Date = .now) -> Double? {
        guard let lastTrainedDate else { return nil }
        return asOf.timeIntervalSince(lastTrainedDate) / 3600
    }

    /// Grobe verbleibende Stunden bis zur kurzfristigen Erholung (siehe
    /// `MuscleGroup.typicalRecoveryHours`) - 0, sobald das Zeitfenster
    /// abgelaufen ist. Bewusst getrennt von `fatigueLevel`/ACWR: das ist ein
    /// Langfrist-Trainingskonsistenz-Indikator (Wochen), dieser Wert hier
    /// beantwortet die kurzfristige Frage "seit wann/wie lange noch bis zur
    /// Erholung von der LETZTEN Einheit".
    public func recoveryHoursRemaining(asOf: Date = .now) -> Double? {
        guard let hours = hoursSinceLastTrained(asOf: asOf) else { return nil }
        return max(0, muscle.typicalRecoveryHours - hours)
    }

    /// Kurzfristiger "heute trainierbar?"-Status - siehe `ShortTermReadiness`.
    public func shortTermReadiness(asOf: Date = .now) -> ShortTermReadiness {
        guard let remaining = recoveryHoursRemaining(asOf: asOf) else { return .noData }
        return remaining > 0 ? .recovering(hoursRemaining: remaining) : .ready
    }
}

/// Leitet aus einer Historie von Belastungsimpulsen (`MuscleLoadEvent`) pro Muskel
/// eine akute/chronische Trainingslast ab (EWMA-basiertes ACWR-Modell, angelehnt an
/// den in der Sportwissenschaft gebräuchlichen Ansatz von Williams et al. 2016).
/// So lässt sich abschätzen, welche Muskeln aktuell stark beansprucht und noch nicht
/// regeneriert sind.
public enum MuscleLoadCalculator {

    private static let acuteSpanDays = 3.0
    private static let chronicSpanDays = 28.0

    /// Ab dieser Anzahl Tage seit dem ersten Belastungs-Ereignis für einen
    /// Muskel wird die chronische (28-Tage-)Basis als aussagekräftig genug
    /// angesehen, um daraus "erhöhte"/"hohe Belastung" abzuleiten. Direkt am
    /// Anfang (z.B. die erste jemals getrackte Einheit für einen bestimmten
    /// Muskel, oder wenn `.cardio`-Events neu hinzugekommen sind) ist die
    /// chronische EWMA noch kaum eingeschwungen (praktisch 0) - dadurch würde
    /// selbst eine einzelne moderate Einheit rechnerisch ein extremes
    /// Verhältnis ergeben und fälschlich als Überlastung erscheinen, obwohl
    /// es sich nur um einen Kaltstart-Effekt ohne echte Vergleichsbasis handelt.
    private static let minHistoryDaysForElevatedClassification = 14

    /// Vergleichszeitraum für die Wiedereinstiegs-Erkennung (siehe
    /// `MuscleLoadStatus.isRampingUp`): die chronische Basis von JETZT wird
    /// mit der von vor `rampingUpLookbackDays` Tagen verglichen. Bewusst
    /// gegen einen festen Zeitpunkt in der Vergangenheit statt gegen den
    /// eigenen historischen Höchststand (`maxEverChronic`) - ein reiner
    /// Höchststand-Vergleich erkennt nur "war mal höher, jetzt wieder
    /// niedriger, jetzt wieder im Aufbau", verpasst aber den mindestens
    /// genauso häufigen Fall "wurde noch NIE nennenswert trainiert und baut
    /// gerade zum ERSTEN Mal auf" - dort ist die aktuelle chronische Basis
    /// selbst der bisherige Höchststand (monoton steigend), der alte
    /// Vergleich würde also nie auslösen.
    private static let rampingUpLookbackDays = 21.0

    /// Weichen "jetzt" und "vor `rampingUpLookbackDays` Tagen" um mehr als
    /// diesen Faktor voneinander ab (in JEDE Richtung: deutlich höher ODER
    /// deutlich niedriger als vorher), gilt das als "Wiedereinstieg nach
    /// ruhigerer Zeit" (siehe `MuscleLoadStatus.isRampingUp`) statt als
    /// bereits stabile hohe Basis, auf die zusätzlich draufkommt - ein hohes
    /// ACWR-Verhältnis entsteht in diesem Fall vor allem durch einen gerade
    /// erst im Umbruch befindlichen Nenner, nicht durch eine tatsächlich
    /// stabile hohe Gesamtbelastung. Die Einstufung wird dann um eine Stufe
    /// abgefedert (siehe unten), aber nicht komplett unterdrückt - ein
    /// schneller Anstieg bleibt laut ACWR-Forschung ein Risikofaktor,
    /// unabhängig vom Grund dafür.
    private static let rampingUpChronicThreshold = 0.5

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

        let lookbackDate = calendar.date(byAdding: .day, value: -Int(rampingUpLookbackDays), to: today) ?? today

        var ewmaAcute = 0.0
        var ewmaChronic = 0.0
        var ewmaChronicAtLookback = 0.0
        var passedLookback = false
        var cursor = firstDate
        var lastTrainedDay: Date?

        while cursor <= today {
            let volume = dailyVolume[cursor] ?? 0
            if volume > 0 { lastTrainedDay = cursor }
            ewmaAcute = volume * lambdaAcute + ewmaAcute * (1 - lambdaAcute)
            ewmaChronic = volume * lambdaChronic + ewmaChronic * (1 - lambdaChronic)
            if !passedLookback && cursor >= lookbackDate {
                ewmaChronicAtLookback = ewmaChronic
                passedLookback = true
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if !passedLookback { ewmaChronicAtLookback = ewmaChronic }

        let acwr = ewmaChronic > 0.01 ? ewmaAcute / ewmaChronic : (ewmaAcute > 0 ? 2.0 : 0)
        let daysSince = lastTrainedDay.flatMap { calendar.dateComponents([.day], from: $0, to: today).day }

        let daysOfHistory = calendar.dateComponents([.day], from: firstDate, to: today).day ?? 0
        let hasEnoughHistory = daysOfHistory >= minHistoryDaysForElevatedClassification
        // Ohne genug Historie nach oben auf den "optimal"-Bereich gedeckelt,
        // statt einen Kaltstart-Ausschlag als "erhöht"/"hoch" zu werten (siehe
        // `minHistoryDaysForElevatedClassification`) - `acwr` selbst bleibt
        // unten im Status unverändert für Transparenz/Debugging erhalten.
        let classificationAcwr = hasEnoughHistory ? acwr : min(acwr, 1.3)

        // Siehe `rampingUpChronicThreshold`-Kommentar: weicht die aktuelle
        // chronische Basis stark von der vor `rampingUpLookbackDays` Tagen ab
        // (in beide Richtungen), ist der Nenner gerade erst im Umbruch statt
        // stabil hoch - ein hohes ACWR kommt dann eher daher als von bereits
        // hoher Gesamtbelastung.
        let chronicDivergenceRatio: Double = {
            let lo = min(ewmaChronic, ewmaChronicAtLookback)
            let hi = max(ewmaChronic, ewmaChronicAtLookback)
            guard hi > 0.01 else { return 1.0 }
            return lo / hi
        }()
        let isRampingUp = ewmaChronic > 0.01 && chronicDivergenceRatio < rampingUpChronicThreshold

        var level: FatigueLevel
        if ewmaChronic <= 0.01 && ewmaAcute <= 0.01 {
            level = .noData
        } else if classificationAcwr < 0.8 {
            level = .fresh
        } else if classificationAcwr <= 1.3 {
            level = .optimal
        } else if classificationAcwr <= 1.5 {
            level = .elevated
        } else {
            level = .highStrain
        }
        // Um eine Stufe abfedern statt komplett unterdrücken - ein schneller
        // Anstieg bleibt ein Risikofaktor, soll aber nicht wie eine bereits
        // bestehende Überlastung wirken, wenn die Basis dafür noch niedrig ist.
        if isRampingUp {
            if level == .highStrain { level = .elevated }
            else if level == .elevated { level = .optimal }
        }

        // Bevorzugt die letzte PRIMÄRE Belastung für die kurzfristige
        // Erholungsuhr (siehe `recoveryHoursRemaining`) - sonst würde z.B. ein
        // Lauf (Beine nur sekundär mit halbem Volumen mitbelastet) dieselbe
        // 70+h-Uhr auslösen wie ein gezieltes Bein-Training, obwohl die
        // tatsächliche Belastung für diesen Muskel dabei viel geringer war.
        // Nur falls ein Muskel noch NIE primäres Ziel einer Übung war (z.B.
        // Unterarme, die fast überall nur sekundär vorkommen), auf jede
        // Belastung zurückfallen - besser eine grobe Angabe als gar keine.
        let primaryEvents = events.filter { $0.isPrimary && $0.volume > 0 }
        let lastTrainedDate = (primaryEvents.isEmpty ? events.filter { $0.volume > 0 } : primaryEvents).map(\.date).max()

        return MuscleLoadStatus(
            muscle: muscle,
            acuteLoad: ewmaAcute,
            chronicLoad: ewmaChronic,
            acwr: acwr,
            fatigueLevel: level,
            daysSinceLastTrained: daysSince,
            lastTrainedDate: lastTrainedDate,
            isRampingUp: isRampingUp
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
