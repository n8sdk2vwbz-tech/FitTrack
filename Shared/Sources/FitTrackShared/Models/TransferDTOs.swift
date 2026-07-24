import Foundation

// MARK: - Plan transfer (iPhone -> Watch)
// Leichtgewichtige, reine Codable-Struktur, damit sie unabhängig vom
// SwiftData-Modell des iPhones per WatchConnectivity verschickt werden kann.

public struct PlanItemDTO: Codable, Identifiable, Hashable {
    public let id: String
    public let exerciseId: String
    public let exerciseName: String
    public let targetSets: Int
    public let targetReps: Int
    /// Obere Grenze, falls die Ziel-Wdh. als Spanne angegeben sind (siehe `PlanItem.targetRepsMax`).
    public let targetRepsMax: Int?
    public let targetWeightKg: Double?

    public init(id: String, exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, targetRepsMax: Int? = nil, targetWeightKg: Double?) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRepsMax = targetRepsMax
        self.targetWeightKg = targetWeightKg
    }
}

public struct PlanDayDTO: Codable, Identifiable, Hashable {
    public let id: String
    public let planName: String
    public let dayName: String
    public let items: [PlanItemDTO]

    public init(id: String, planName: String, dayName: String, items: [PlanItemDTO]) {
        self.id = id
        self.planName = planName
        self.dayName = dayName
        self.items = items
    }
}

// MARK: - Workout result transfer (Watch -> iPhone)

public struct CompletedSetDTO: Codable, Hashable {
    public let reps: Int
    public let weightKg: Double
    public let isWarmup: Bool

    public init(reps: Int, weightKg: Double, isWarmup: Bool) {
        self.reps = reps
        self.weightKg = weightKg
        self.isWarmup = isWarmup
    }
}

public struct CompletedExerciseDTO: Codable, Identifiable, Hashable {
    public let id: String
    public let exerciseId: String
    public let exerciseName: String
    public let sets: [CompletedSetDTO]

    public init(id: String, exerciseId: String, exerciseName: String, sets: [CompletedSetDTO]) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

public struct CompletedWorkoutDTO: Codable, Identifiable, Hashable {
    public let id: String
    public let startDate: Date
    public let endDate: Date
    public let activityName: String
    public let totalEnergyBurnedKcal: Double?
    public let averageHeartRate: Double?
    public let exercises: [CompletedExerciseDTO]
    public let healthKitWorkoutUUID: String?

    public init(id: String, startDate: Date, endDate: Date, activityName: String, totalEnergyBurnedKcal: Double?, averageHeartRate: Double?, exercises: [CompletedExerciseDTO], healthKitWorkoutUUID: String?) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activityName = activityName
        self.totalEnergyBurnedKcal = totalEnergyBurnedKcal
        self.averageHeartRate = averageHeartRate
        self.exercises = exercises
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
    }
}

// MARK: - Remote heart-rate monitoring (iPhone-initiated, Watch-measured)
// HealthKit's Workout-Mirroring API only mirrors Watch -> iPhone, never the
// other way round (a workout session with live sensor data can only run on
// the Watch, since that's where the sensors are). To let a workout that was
// started on the iPhone still be measured by the Watch, the iPhone asks the
// Watch to start its own `HKWorkoutSession` and streams the live heart rate
// back over WatchConnectivity while both devices are reachable.

public struct RemoteWorkoutStartDTO: Codable, Hashable {
    public let sessionId: String
    public let activityName: String
    /// Aktueller Stand der Satzpausen-Timer-Einstellung (siehe
    /// `WatchConnectivityManager.restTimerEnabled`) - wird hier zusätzlich zur
    /// separat per `updateApplicationContext` synchronisierten Einstellung
    /// mitgeschickt, da diese Nachricht (mit eingebauter Zustellungs-
    /// Wiederholung bei fehlender Erreichbarkeit, siehe `ActiveWorkoutView.
    /// sendStartRequest`) beim eigentlichen Trainingsstart zuverlässiger
    /// ankommt als der reine Kontext-Sync.
    public let restTimerEnabled: Bool

    public init(sessionId: String, activityName: String, restTimerEnabled: Bool = false) {
        self.sessionId = sessionId
        self.activityName = activityName
        self.restTimerEnabled = restTimerEnabled
    }
}

public struct RemoteWorkoutStopDTO: Codable, Hashable {
    public let sessionId: String
    /// true, wenn das Training abgebrochen (nicht regulär beendet) wurde -
    /// die Watch soll dann ihre HKWorkoutSession verwerfen (`discardWorkout`)
    /// statt sie als echtes HealthKit-Workout zu speichern.
    public let discard: Bool

    public init(sessionId: String, discard: Bool = false) {
        self.sessionId = sessionId
        self.discard = discard
    }
}

public struct HeartRateUpdateDTO: Codable, Hashable {
    public let sessionId: String
    public let bpm: Double

    public init(sessionId: String, bpm: Double) {
        self.sessionId = sessionId
        self.bpm = bpm
    }
}

/// Watch -> iPhone: Stand der Satzpausen-Überwachung, damit `ActiveWorkoutView`
/// dieselbe Anzeige ("Pause: Xs") wie die Watch zeigen und bei Abschluss
/// (`isActive` wird false) eine lokale Mitteilung auslösen kann.
public struct RestTimerStatusDTO: Codable, Hashable {
    public let sessionId: String
    public let isActive: Bool
    public let elapsedSeconds: Double
    /// Angestrebte Herzfrequenz, ab der die Pause als beendet gilt (siehe
    /// `WorkoutManager.restTargetHeartRate`) - v.a. zum Testen/Kalibrieren der
    /// Formel auf dem iPhone/in der Live Activity mit angezeigt.
    public let targetHeartRate: Double?

    public init(sessionId: String, isActive: Bool, elapsedSeconds: Double, targetHeartRate: Double? = nil) {
        self.sessionId = sessionId
        self.isActive = isActive
        self.elapsedSeconds = elapsedSeconds
        self.targetHeartRate = targetHeartRate
    }
}

/// iPhone -> Watch: ein Satz wurde in einem ferngesteuerten Training gerade
/// abgehakt - löst auf der Watch (die die Herzfrequenz misst) die HF-basierte
/// Satzpausen-Überwachung aus (siehe `WorkoutManager.startRestMonitoringIfNeeded`).
/// Beim lokal auf der Watch geloggten Training braucht es diese Nachricht
/// nicht, da `WorkoutManager.logSet` direkt selbst auslöst.
public struct RestTimerTriggerDTO: Codable, Hashable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}

/// Watch -> iPhone: der Nutzer hat einen Satz direkt auf der Watch abgehakt
/// (ohne die iPhone-App zu öffnen, siehe `RemoteMonitoringView`). Die Watch
/// kennt bei einem ferngesteuerten Training den Plan/die Satzliste nicht -
/// das iPhone markiert deshalb selbst den nächsten noch offenen Satz als
/// erledigt, in derselben Reihenfolge wie beim manuellen Abhaken dort.
public struct RemoteSetCompletedDTO: Codable, Hashable {
    public let sessionId: String
    /// Eindeutig pro Tastendruck (nicht nur die Session-ID) - `ActiveWorkoutView`
    /// erkennt neue Ereignisse über `.onChange(of:)`, das nur bei einer
    /// tatsächlichen Wertänderung auslöst. Ohne dieses Feld wären zwei
    /// Nachrichten für dieselbe Session strukturell identisch, ein zweiter
    /// Tastendruck hätte also nie ausgelöst - es wäre immer beim ersten Satz
    /// geblieben.
    public let eventId: String

    public init(sessionId: String, eventId: String = UUID().uuidString) {
        self.sessionId = sessionId
        self.eventId = eventId
    }
}

public struct RemoteWorkoutResultDTO: Codable, Hashable {
    public let sessionId: String
    public let startDate: Date
    public let endDate: Date
    public let totalEnergyBurnedKcal: Double?
    public let averageHeartRate: Double?
    public let healthKitWorkoutUUID: String?

    public init(sessionId: String, startDate: Date, endDate: Date, totalEnergyBurnedKcal: Double?, averageHeartRate: Double?, healthKitWorkoutUUID: String?) {
        self.sessionId = sessionId
        self.startDate = startDate
        self.endDate = endDate
        self.totalEnergyBurnedKcal = totalEnergyBurnedKcal
        self.averageHeartRate = averageHeartRate
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
    }
}

// MARK: - Plan sharing (Export/Import zwischen Geräten/Nutzern per Link/QR-Code)
// Bewusst OHNE Gewichte, Steigerungs-Merker und Alternativen - das sind
// persönliche Fortschritts-/Geräte-Daten, die beim Teilen eines Plans nicht
// sinnvoll auf eine andere Person übertragbar sind. Notizen werden bewusst
// übernommen. Kurze CodingKeys, damit der codierte Link/QR-Code möglichst
// kompakt bleibt (siehe `PlanSharePayload`).

public struct SharedPlanItemDTO: Codable, Hashable {
    public let exerciseId: String
    public let exerciseName: String
    public let targetSets: Int
    public let targetReps: Int
    /// Obere Grenze, falls die Ziel-Wdh. als Spanne angegeben sind (siehe `PlanItem.targetRepsMax`).
    public let targetRepsMax: Int?
    public let warmupSetCount: Int
    public let notes: String

    private enum CodingKeys: String, CodingKey {
        case exerciseId = "e"
        case exerciseName = "n"
        case targetSets = "s"
        case targetReps = "r"
        case targetRepsMax = "x"
        case warmupSetCount = "w"
        case notes = "o"
    }

    public init(exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, targetRepsMax: Int? = nil, warmupSetCount: Int, notes: String) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetRepsMax = targetRepsMax
        self.warmupSetCount = warmupSetCount
        self.notes = notes
    }
}

public struct SharedPlanDayDTO: Codable, Hashable {
    public let name: String
    public let items: [SharedPlanItemDTO]

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case items = "i"
    }

    public init(name: String, items: [SharedPlanItemDTO]) {
        self.name = name
        self.items = items
    }
}

public struct SharedPlanDTO: Codable, Hashable {
    public let name: String
    public let notes: String
    public let days: [SharedPlanDayDTO]

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case notes = "o"
        case days = "d"
    }

    public init(name: String, notes: String, days: [SharedPlanDayDTO]) {
        self.name = name
        self.notes = notes
        self.days = days
    }
}

extension SharedPlanDTO: Identifiable {
    /// Für `.sheet(item:)` beim Import - keine persistente Identität nötig,
    /// da dieser Wert nur kurzlebig für den Bestätigungs-Dialog existiert.
    public var id: Int { hashValue }
}

// MARK: - Muscle load transfer events

/// Ein einzelner, zeitlich verorteter Belastungsimpuls auf einen Muskel.
/// Wird aus vergangenen Workouts abgeleitet und von `MuscleLoadCalculator`
/// sowie `RecoveryEngine` konsumiert. Plattformunabhängig (kein SwiftData).
public struct MuscleLoadEvent: Codable, Hashable {
    public let date: Date
    public let muscle: MuscleGroup
    public let volume: Double
    /// Ob dieser Muskel bei dieser Übung primäres Ziel war (statt nur mit
    /// halbem Volumen sekundär mitbelastet, siehe
    /// `WorkoutSession.muscleLoadEvents`) - z.B. Beine bei einem Lauf sind nur
    /// sekundär betroffen. `MuscleLoadCalculator` nutzt das, um die
    /// kurzfristige Erholungsuhr (siehe `recoveryHoursRemaining`) nicht schon
    /// durch eine beiläufige Mitbelastung aus einer ganz anderen Trainingsart
    /// neu zu starten.
    public let isPrimary: Bool

    public init(date: Date, muscle: MuscleGroup, volume: Double, isPrimary: Bool = true) {
        self.date = date
        self.muscle = muscle
        self.volume = volume
        self.isPrimary = isPrimary
    }
}
