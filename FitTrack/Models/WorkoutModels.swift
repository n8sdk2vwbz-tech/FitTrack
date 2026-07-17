import Foundation
import SwiftData
import HealthKit
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
    /// `HKWorkoutActivityType.rawValue` des importierten HealthKit-Workouts
    /// (z.B. Laufen, Radfahren) - erlaubt `muscleLoadEvents()`, auch für
    /// Ausdauertrainings ohne eigene `ExerciseEntry`-Sätze eine sinnvolle
    /// Muskel-Belastung abzuleiten (siehe `cardioExerciseLibraryId`).
    var healthKitActivityTypeRawValue: Int?
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
        healthKitActivityTypeRawValue: Int? = nil,
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
        self.healthKitActivityTypeRawValue = healthKitActivityTypeRawValue
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
        let hrFactor: Double? = {
            guard let avgHR = averageHeartRate, avgHR > 0 else { return nil }
            let reference = maxHeartRate.map { $0 * 0.65 } ?? 130.0
            return min(max(avgHR / reference, 0.6), 1.8)
        }()

        if let rpe = perceivedExertion {
            let rpeFactor = Double(rpe) / 5.0 // RPE 5 ("moderat") = neutral, 1.0x
            guard let hrFactor else { return rpeFactor }
            // RPE bleibt bei Krafttraining das zuverlässigere Signal: die
            // Herzfrequenz bleibt durch Satzpausen strukturell niedriger als
            // bei durchgehender Ausdauerbelastung, selbst wenn sich die
            // Einheit sehr hart anfühlt - ein 50/50-Mix würde ein bewusst
            // hoch eingeschätztes RPE sonst unpassend verwässern. Die
            // Herzfrequenz fließt nur noch als kleinerer Korrekturfaktor ein.
            return rpeFactor * 0.8 + hrFactor * 0.2
        }
        return hrFactor ?? 1.0
    }

    /// Näherungsweise Belastung pro Trainingsminute für importierte
    /// Ausdauertrainings ohne Satz-/Wiederholungsdaten (siehe unten). Da
    /// unten pro betroffenem Muskel ein eigenes Event mit (bei sekundären
    /// Muskeln halbem) `totalVolume` erzeugt wird, addiert sich die je
    /// Session tatsächlich in `recentSessionLoad` einfließende Summe auf das
    /// ca. 2-2.5-fache von `totalVolume` (1 primärer Cardio-Muskel + 2-3
    /// sekundäre Muskeln je Übung in der Bibliothek) - der Wert hier ist
    /// entsprechend niedriger angesetzt, damit eine ca. 40-minütige, moderat
    /// intensive Einheit nach dieser Aufsummierung bei einer mit einer
    /// durchschnittlichen Kraft-Einheit vergleichbaren Gesamtbelastung landet
    /// (vgl. `RecoveryEngine.typicalSessionLoad`), statt sie dafür deutlich
    /// zu überzeichnen.
    private static let cardioLoadPerMinute = 15.0

    /// Leitet aus allen Sätzen die Belastungs-Impulse pro Muskel ab, anhand
    /// der primären/sekundären Muskeln jeder Übung aus der Bibliothek,
    /// skaliert mit `intensityMultiplier` (RPE + Trainings-Herzfrequenz). Für
    /// aus HealthKit importierte Ausdauertrainings (z.B. Laufen, Radfahren),
    /// die keine `ExerciseEntry`-Sätze haben, wird stattdessen anhand von
    /// Dauer und Trainings-Herzfrequenz sowie der Muskelzuordnung der
    /// passenden Cardio-Übung aus `ExerciseLibrary` eine Belastung
    /// abgeleitet - so fließt z.B. ein hartes Lauftraining auch in die
    /// Bein-Ermüdung und die Gesamt-Bereitschaft ein, nicht nur reine
    /// Kraft-Sessions.
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

        if entries.isEmpty,
           let rawActivityType = healthKitActivityTypeRawValue,
           let cardioExerciseId = HKWorkoutActivityType(rawValue: UInt(rawActivityType))?.cardioExerciseLibraryId,
           let exercise = ExerciseLibrary.byId[cardioExerciseId] {
            let totalVolume = (durationSeconds / 60.0) * Self.cardioLoadPerMinute * intensity
            if totalVolume > 0.01 {
                for muscle in exercise.primaryMuscles {
                    events.append(MuscleLoadEvent(date: date, muscle: muscle, volume: totalVolume))
                }
                for muscle in exercise.secondaryMuscles {
                    events.append(MuscleLoadEvent(date: date, muscle: muscle, volume: totalVolume * 0.5))
                }
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
    /// Ausweich-Übungen mit denselben Ziel-Muskeln (gleicher Index in beiden
    /// Arrays), z.B. falls ein Gerät im Gym nicht verfügbar ist. Nur vom
    /// Plan-Generator befüllt, bei manuell hinzugefügten Übungen leer.
    var alternativeExerciseIds: [String] = []
    var alternativeExerciseNames: [String] = []

    init(exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, targetWeightKg: Double? = nil, warmupSetCount: Int = 0, order: Int = 0, alternativeExerciseIds: [String] = [], alternativeExerciseNames: [String] = []) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.warmupSetCount = warmupSetCount
        self.order = order
        self.alternativeExerciseIds = alternativeExerciseIds
        self.alternativeExerciseNames = alternativeExerciseNames
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
