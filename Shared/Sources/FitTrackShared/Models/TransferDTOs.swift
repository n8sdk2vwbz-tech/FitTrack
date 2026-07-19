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
    public let targetWeightKg: Double?

    public init(id: String, exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, targetWeightKg: Double?) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
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

    public init(sessionId: String, activityName: String) {
        self.sessionId = sessionId
        self.activityName = activityName
    }
}

public struct RemoteWorkoutStopDTO: Codable, Hashable {
    public let sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
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
    public let warmupSetCount: Int
    public let notes: String

    private enum CodingKeys: String, CodingKey {
        case exerciseId = "e"
        case exerciseName = "n"
        case targetSets = "s"
        case targetReps = "r"
        case warmupSetCount = "w"
        case notes = "o"
    }

    public init(exerciseId: String, exerciseName: String, targetSets: Int, targetReps: Int, warmupSetCount: Int, notes: String) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.targetReps = targetReps
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

    public init(date: Date, muscle: MuscleGroup, volume: Double) {
        self.date = date
        self.muscle = muscle
        self.volume = volume
    }
}
