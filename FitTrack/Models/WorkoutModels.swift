import Foundation
import SwiftData
import FitTrackShared

enum WorkoutSource: String, Codable {
    case iphone
    case watch
    /// Aus HealthKit importiertes Workout, das eine andere App aufgezeichnet hat
    /// (z.B. die native Watch Workout-App oder Strava) - analog zu Stravas
    /// automatischem Health-Import.
    case health
}

@Model
final class SetEntry {
    var reps: Int
    var weightKg: Double
    var rpe: Double?
    var isWarmup: Bool
    var order: Int

    init(reps: Int, weightKg: Double, rpe: Double? = nil, isWarmup: Bool = false, order: Int = 0) {
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.order = order
    }

    var volume: Double {
        let effectiveWeight = weightKg > 0 ? weightKg : 20 // Körpergewichts-Näherung für Belastungsindex
        return Double(reps) * effectiveWeight
    }
}

@Model
final class ExerciseEntry {
    var exerciseId: String
    var exerciseName: String
    var order: Int
    @Relationship(deleteRule: .cascade) var sets: [SetEntry]

    init(exerciseId: String, exerciseName: String, order: Int = 0, sets: [SetEntry] = []) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.order = order
        self.sets = sets
    }

    /// Kompakte Zusammenfassung der Arbeitssätze, z.B. "10x20,0 kg, 8x22,5 kg".
    var summaryText: String {
        let workingSets = sets.filter { !$0.isWarmup }.sorted { $0.order < $1.order }
        guard !workingSets.isEmpty else { return "–" }
        return workingSets
            .map { "\($0.reps)x\($0.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg" }
            .joined(separator: ", ")
    }

    var topSetWeight: Double {
        sets.filter { !$0.isWarmup }.map(\.weightKg).max() ?? 0
    }

    var totalVolume: Double {
        sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
    }
}

@Model
final class WorkoutSession {
    var id: String
    var date: Date
    var activityName: String
    var durationSeconds: Double
    var totalEnergyBurnedKcal: Double?
    var averageHeartRate: Double?
    var distanceMeters: Double?
    /// Name der App, die dieses Workout ursprünglich aufgezeichnet hat
    /// (z.B. "Workout" für die native Watch-App oder "Strava"), sofern importiert.
    var externalSourceName: String?
    var sourceRaw: String
    var healthKitWorkoutUUID: String?
    /// Gefühlte Anstrengung (RPE, 1-10), manuell nach dem Training bewertet -
    /// ähnlich Apples "Anstrengung bewerten". Fließt zusammen mit der
    /// Herzfrequenz in die Trainingslast-Berechnung ein (siehe `intensityMultiplier`).
    var perceivedExertion: Int?
    @Relationship(deleteRule: .cascade) var entries: [ExerciseEntry]

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .iphone }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        date: Date = .now,
        activityName: String,
        durationSeconds: Double,
        totalEnergyBurnedKcal: Double? = nil,
        averageHeartRate: Double? = nil,
        distanceMeters: Double? = nil,
        externalSourceName: String? = nil,
        source: WorkoutSource = .iphone,
        healthKitWorkoutUUID: String? = nil,
        perceivedExertion: Int? = nil,
        entries: [ExerciseEntry] = []
    ) {
        self.id = id
        self.date = date
        self.activityName = activityName
        self.durationSeconds = durationSeconds
        self.totalEnergyBurnedKcal = totalEnergyBurnedKcal
        self.averageHeartRate = averageHeartRate
        self.distanceMeters = distanceMeters
        self.externalSourceName = externalSourceName
        self.sourceRaw = source.rawValue
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.perceivedExertion = perceivedExertion
        self.entries = entries
    }

    /// Kombinierter Intensitätsfaktor aus gefühlter Anstrengung (RPE) und
    /// durchschnittlicher Herzfrequenz während des Trainings, sofern vorhanden.
    /// Skaliert das reine Sätze×Wiederholungen×Gewicht-Volumen in
    /// `muscleLoadEvents()`, damit ein subjektiv oder pulsmäßig hartes
    /// Training stärker in die Trainingslast (und damit den Bereitschafts-
    /// Score) einfließt als eines mit identischen Zahlen, aber geringerer
    /// tatsächlicher Anstrengung. Ohne RPE/Herzfrequenz bleibt der Faktor 1.0
    /// (reines Volumen wie zuvor).
    ///
    /// - Parameter maxHeartRate: Geschätzte individuelle HFmax (aus dem in
    ///   Health hinterlegten Geburtsdatum, siehe `HealthKitManager.fetchEstimatedMaxHeartRate`).
    ///   Ist sie bekannt, wird die Trainings-Herzfrequenz relativ zu 65% davon
    ///   bewertet statt gegen einen festen 130-bpm-Richtwert - das
    ///   berücksichtigt Alter/individuelle Fitness statt für alle denselben
    ///   Absolutwert anzusetzen.
    func intensityMultiplier(maxHeartRate: Double? = nil) -> Double {
        var factors: [Double] = []
        if let rpe = perceivedExertion {
            factors.append(Double(rpe) / 5.0) // RPE 5 ("moderat") = neutral, 1.0x
        }
        if let avgHR = averageHeartRate, avgHR > 0 {
            let reference = maxHeartRate.map { $0 * 0.65 } ?? 130.0
            factors.append(min(max(avgHR / reference, 0.6), 1.8))
        }
        guard !factors.isEmpty else { return 1.0 }
        return factors.reduce(0, +) / Double(factors.count)
    }

    /// Leitet aus allen Sätzen die Belastungs-Impulse pro Muskel ab, anhand
    /// der primären/sekundären Muskeln jeder Übung aus der Bibliothek,
    /// skaliert mit `intensityMultiplier` (RPE + Trainings-Herzfrequenz).
    func muscleLoadEvents(maxHeartRate: Double? = nil) -> [MuscleLoadEvent] {
        var events: [MuscleLoadEvent] = []
        let intensity = intensityMultiplier(maxHeartRate: maxHeartRate)
        for entry in entries {
            guard let exercise = ExerciseLibrary.byId[entry.exerciseId] else { continue }
            let baseVolume = entry.sets.filter { !$0.isWarmup }.reduce(0) { $0 + $1.volume }
            guard baseVolume > 0 else { continue }
            let totalVolume = baseVolume * intensity
            for muscle in exercise.primaryMuscles {
                events.append(MuscleLoadEvent(date: date, muscle: muscle, volume: totalVolume))
            }
            for muscle in exercise.secondaryMuscles {
                events.append(MuscleLoadEvent(date: date, muscle: muscle, volume: totalVolume * 0.5))
            }
        }
        return events
    }

    /// Findet den letzten geloggten Satz-Eintrag für eine Übung, quer über alle Sessions.
    /// Wird genutzt, um beim Start eines Trainings die letzte Leistung als Referenz anzuzeigen.
    static func mostRecentEntry(forExerciseId exerciseId: String, in sessions: [WorkoutSession]) -> ExerciseEntry? {
        sessions
            .sorted { $0.date > $1.date }
            .compactMap { session in session.entries.first { $0.exerciseId == exerciseId } }
            .first
    }

    /// Verlauf von Top-Satz-Gewicht und Gesamtvolumen für eine Übung, älteste zuerst.
    static func history(forExerciseId exerciseId: String, in sessions: [WorkoutSession]) -> [(date: Date, topWeight: Double, volume: Double)] {
        sessions
            .sorted { $0.date < $1.date }
            .compactMap { session -> (Date, Double, Double)? in
                guard let entry = session.entries.first(where: { $0.exerciseId == exerciseId }) else { return nil }
                guard entry.totalVolume > 0 else { return nil }
                return (session.date, entry.topSetWeight, entry.totalVolume)
            }
            .map { (date: $0.0, topWeight: $0.1, volume: $0.2) }
    }
}

/// Pläne (`TrainingPlan`/`PlanDay`/`PlanItem`) werden über iCloud synchronisiert
/// (siehe `FitTrackApp.makeModelContainer`), der Trainings-Verlauf bleibt rein
/// lokal. SwiftDatas CloudKit-Sync verlangt dafür: jede Property braucht einen
/// Default-Wert (oder ist optional), und alle Beziehungen müssen optional
/// sein - deshalb `items`/`days` als `Optional` mit den bequemen, nie-nil
/// Zugriffs-Properties `itemList`/`dayList` für den Rest der App.
@Model
final class PlanItem {
    var exerciseId: String = ""
    var exerciseName: String = ""
    var targetSets: Int = 3
    var targetReps: Int = 10
    /// Dient zugleich als Gedächtnis: wird nach jedem Training mit dieser
    /// Übung an dieser Stelle im Plan auf das zuletzt genutzte Gewicht
    /// aktualisiert, damit sie beim nächsten Mal automatisch vorausgefüllt
    /// ist - unabhängig davon, ob dieselbe Übung in einem anderen Plan oder
    /// Trainingstag mit einem anderen Gewicht geführt wird.
    var targetWeightKg: Double?
    var warmupSetCount: Int = 0
    var order: Int = 0

    init(exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, targetWeightKg: Double? = nil, warmupSetCount: Int = 0, order: Int = 0) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.warmupSetCount = warmupSetCount
        self.order = order
    }

    func toDTO() -> PlanItemDTO {
        PlanItemDTO(id: UUID().uuidString, exerciseId: exerciseId, exerciseName: exerciseName, targetSets: targetSets, targetReps: targetReps, targetWeightKg: targetWeightKg)
    }
}

@Model
final class PlanDay {
    var name: String = ""
    var order: Int = 0
    @Relationship(deleteRule: .cascade) var items: [PlanItem]?

    init(name: String, order: Int = 0, items: [PlanItem] = []) {
        self.name = name
        self.order = order
        self.items = items
    }

    var itemList: [PlanItem] {
        get { items ?? [] }
        set { items = newValue }
    }
}

@Model
final class TrainingPlan {
    var id: String = UUID().uuidString
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade) var days: [PlanDay]?

    init(id: String = UUID().uuidString, name: String, notes: String = "", createdAt: Date = .now, days: [PlanDay] = []) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.days = days
    }

    var dayList: [PlanDay] {
        get { days ?? [] }
        set { days = newValue }
    }
}
