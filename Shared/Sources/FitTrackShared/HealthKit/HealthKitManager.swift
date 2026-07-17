import Foundation
import HealthKit

public struct SleepSummary {
    public let asleepHours: Double
    public let efficiency: Double?
}

public struct WorkoutSummary {
    public let energyKcal: Double?
    public let averageHeartRate: Double?
    public let distanceMeters: Double?
    /// Name der App, die das Workout aufgezeichnet hat (z.B. "Workout", "Strava").
    public let sourceName: String?
}

/// Kapselt allen HealthKit-Zugriff (Lesen von Schlaf/HRV/Ruhepuls, Schreiben
/// von Workouts). Läuft identisch auf iPhone und Watch, da beide Plattformen
/// HealthKit unterstützen und über den iCloud-Health-Sync dieselben Daten sehen.
public final class HealthKitManager {

    public static let shared = HealthKitManager()

    public let healthStore = HKHealthStore()

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private let restingHRType = HKQuantityType(.restingHeartRate)
    private let heartRateType = HKQuantityType(.heartRate)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private let stepCountType = HKQuantityType(.stepCount)
    private let distanceWalkingRunningType = HKQuantityType(.distanceWalkingRunning)
    private let distanceCyclingType = HKQuantityType(.distanceCycling)
    private let workoutType = HKObjectType.workoutType()
    private let bodyMassType = HKQuantityType(.bodyMass)
    private let dateOfBirthType = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private init() {}

    public func requestAuthorization() async throws {
        guard isHealthDataAvailable else { return }
        var readTypes: Set<HKObjectType> = [
            sleepType, hrvType, restingHRType, heartRateType, activeEnergyType,
            stepCountType, distanceWalkingRunningType, distanceCyclingType, workoutType, bodyMassType
        ]
        if let dateOfBirthType { readTypes.insert(dateOfBirthType) }
        let writeTypes: Set<HKSampleType> = [workoutType, activeEnergyType, heartRateType]
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Geschätzte maximale Herzfrequenz anhand des in Health hinterlegten
    /// Geburtsdatums (Tanaka-Formel: 208 - 0.7 × Alter, in Studien präziser
    /// als die ältere Faustregel 220-Alter, v.a. bei älteren Erwachsenen).
    /// Apple stellt keinen eigenen HFmax-Datentyp bereit - dies ist die
    /// gängige Näherung, die auch andere Fitness-Apps ohne Laktattest nutzen.
    /// `nil`, wenn kein Geburtsdatum hinterlegt oder nicht freigegeben ist.
    public func fetchEstimatedMaxHeartRate(now: Date = .now) -> Double? {
        guard let birthDateComponents = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: birthDateComponents) else { return nil }
        guard let age = Calendar.current.dateComponents([.year], from: birthDate, to: now).year, age > 0 else { return nil }
        return 208.0 - 0.7 * Double(age)
    }

    /// Anker für "die letzte Nacht", auf 16 Uhr des Vortags gerundet statt
    /// rein rollierend eine feste Stundenzahl zurückzugehen: Ein
    /// rollierendes Fenster würde bei einer Abfrage später am Tag (z.B.
    /// abends, kurz vor dem nächsten Zubettgehen) bereits mitten in die
    /// letzte Nacht hineinreichen und deren Anfang abschneiden - 16 Uhr
    /// liegt sicher vor jeder üblichen Schlafenszeit, erfasst die komplette
    /// letzte Nacht also unabhängig von der Abfrage-Uhrzeit tagsüber/abends.
    private func lastNightWindowStart(now: Date, calendar: Calendar = .current) -> Date? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return calendar.date(bySettingHour: 16, minute: 0, second: 0, of: yesterday)
    }

    // MARK: - Schlaf

    public func fetchLastNightSleep(now: Date = .now) async -> SleepSummary? {
        guard let windowStart = lastNightWindowStart(now: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictStartDate)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let asleepSamples = samples.filter { asleepValues.contains($0.value) }
        let inBedSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }

        let asleepSeconds = asleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        guard asleepSeconds > 0 else { return nil }

        var efficiency: Double?
        if !inBedSamples.isEmpty {
            let inBedSeconds = inBedSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if inBedSeconds > 0 {
                efficiency = min(asleepSeconds / inBedSeconds, 1.0)
            }
        }

        return SleepSummary(asleepHours: asleepSeconds / 3600.0, efficiency: efficiency)
    }

    // MARK: - Herzratenvariabilität (HRV)

    public func fetchLatestHRV(now: Date = .now) async -> Double? {
        guard let windowStart = lastNightWindowStart(now: now) else { return nil }
        return await fetchAverageQuantity(type: hrvType, unit: HKUnit.secondUnit(with: .milli), from: windowStart, to: now)
    }

    /// Baseline-Fenster endet bewusst dort, wo `fetchLatestHRV`s Fenster
    /// beginnt (nicht bei `now`) - sonst würde dieselbe (aktuelle) Nacht
    /// gleichzeitig als "aktueller Wert" UND als Teil ihrer eigenen
    /// Vergleichsbasis gezählt, was die Basis Richtung aktuellem Wert zieht
    /// und den Score besonders bei wenig Historie künstlich Richtung 100 verzerrt.
    public func fetchHRVBaseline(days: Int = 14, now: Date = .now) async -> Double? {
        guard let latestWindowStart = lastNightWindowStart(now: now),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: latestWindowStart) else { return nil }
        return await fetchAverageQuantity(type: hrvType, unit: HKUnit.secondUnit(with: .milli), from: start, to: latestWindowStart)
    }

    // MARK: - Ruhepuls

    /// Apple berechnet den Ruhepuls als EINEN Tageswert pro Kalendertag (im
    /// Gegensatz zur HRV, für die typischerweise viele Einzelmessungen pro
    /// Nacht vorliegen). Ein zu enges rollierendes 24h-Fenster kann diesen
    /// einen Tageswert knapp verpassen, je nachdem, zu welcher Uhrzeit genau
    /// abgefragt wird und wann genau Apple den Wert für den Tag stempelt -
    /// 2 Tage geben genug Puffer, damit der letzte verfügbare Tageswert
    /// zuverlässig im Fenster liegt, unabhängig von der Abfrage-Uhrzeit.
    private static let restingHRLatestWindowDays = 2

    public func fetchLatestRestingHeartRate(now: Date = .now) async -> Double? {
        await fetchAverageQuantity(type: restingHRType, unit: HKUnit.count().unitDivided(by: .minute()), from: Calendar.current.date(byAdding: .day, value: -Self.restingHRLatestWindowDays, to: now) ?? now, to: now)
    }

    /// Baseline-Fenster endet bewusst dort, wo `fetchLatestRestingHeartRate`s
    /// Fenster beginnt (nicht bei `now`) - siehe Kommentar bei `fetchHRVBaseline`.
    public func fetchRestingHeartRateBaseline(days: Int = 14, now: Date = .now) async -> Double? {
        guard let latestWindowStart = Calendar.current.date(byAdding: .day, value: -Self.restingHRLatestWindowDays, to: now),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: latestWindowStart) else { return nil }
        return await fetchAverageQuantity(type: restingHRType, unit: HKUnit.count().unitDivided(by: .minute()), from: start, to: latestWindowStart)
    }

    private func fetchAverageQuantity(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return total / Double(samples.count)
    }

    // MARK: - Körpergewicht

    /// Für `Exercise`n mit `.bodyweightPlus`/`.bodyweightMinus` (siehe
    /// `BodyWeightCache`) - liefert den zuletzt in Health erfassten
    /// Körpergewichts-Wert, unabhängig davon, wie lange das her ist (anders
    /// als bei Schlaf/HRV/Ruhepuls gibt es hier keinen sinnvollen "richtigen"
    /// Zeitraum - eine Woche oder auch mehrere Monate alte Waage-Messung ist
    /// immer noch die beste verfügbare Näherung).
    public func fetchLatestBodyWeight(daysBack: Int = 365, now: Date = .now) async -> Double? {
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        return samples.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    // MARK: - Workouts speichern (manuelle Erfassung oder Übernahme vom Watch-Ergebnis)

    public func saveWorkout(activityType: HKWorkoutActivityType, start: Date, end: Date, totalEnergyBurnedKcal: Double?, averageHeartRate: Double?) async throws -> HKWorkout {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        try await builder.beginCollection(at: start)

        if let kcal = totalEnergyBurnedKcal, kcal > 0 {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
            let sample = HKQuantitySample(type: activeEnergyType, quantity: quantity, start: start, end: end)
            try await builder.addSamples([sample])
        }

        if let heartRate = averageHeartRate, heartRate > 0 {
            let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: heartRate)
            let sample = HKQuantitySample(type: heartRateType, quantity: quantity, start: start, end: end)
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        return try await builder.finishWorkout() ?? {
            throw HealthKitManagerError.workoutFinishFailed
        }()
    }

    /// Wie `saveWorkout`, aber ohne den Aufrufer zu blockieren: Antwortet
    /// HealthKit nicht innerhalb der Frist (z.B. weil die Berechtigung noch
    /// aussteht oder das System gerade nicht reagiert), wird `nil`
    /// zurückgegeben statt zu werfen oder unbegrenzt zu warten. So kann das
    /// lokale Speichern eines Workouts nie an HealthKit hängen bleiben.
    public func saveWorkoutBestEffort(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        totalEnergyBurnedKcal: Double?,
        averageHeartRate: Double?,
        timeoutSeconds: Double = 5
    ) async -> HKWorkout? {
        await withTaskGroup(of: HKWorkout?.self) { group in
            group.addTask {
                try? await self.saveWorkout(
                    activityType: activityType,
                    start: start,
                    end: end,
                    totalEnergyBurnedKcal: totalEnergyBurnedKcal,
                    averageHeartRate: averageHeartRate
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    #if os(iOS)
    /// Startet/weckt die Watch-App aktiv über HealthKit, statt uns auf
    /// WatchConnectivity `sendMessage` allein zu verlassen. `sendMessage`
    /// scheitert stillschweigend, wenn die Watch-App gerade nicht läuft
    /// (nicht "reachable") - genau dann, wenn sie komplett beendet statt nur
    /// im Hintergrund war. `startWatchApp` ist die von Apple vorgesehene API,
    /// um die Watch-App für ein Training gezielt zu starten, auch wenn sie
    /// noch nicht läuft. Auf der Watch-Seite startet `WatchAppDelegate.handle(_:)`
    /// dafür sofort die passende HKWorkoutSession (siehe dort).
    public func startWatchApp(activityType: HKWorkoutActivityType) async -> Bool {
        guard isHealthDataAvailable else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor
        return await withCheckedContinuation { continuation in
            healthStore.startWatchApp(with: configuration) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
    #endif

    // MARK: - Letzte Workouts (für Historie/Statistik)

    public func fetchRecentWorkouts(daysBack: Int = 90, now: Date = .now) async -> [HKWorkout] {
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Liefert Kalorien, Ø-Herzfrequenz, Distanz und aufzeichnende App für ein
    /// beliebiges HealthKit-Workout - unabhängig davon, welche App es erstellt
    /// hat (native Watch Workout-App, Strava, ...). Nutzt zuerst die im Workout
    /// eingebetteten Statistiken, fällt sonst auf eine Abfrage der verknüpften
    /// Einzel-Samples zurück.
    public func summary(for workout: HKWorkout) async -> WorkoutSummary {
        let energy = await quantitySum(workout: workout, embeddedType: activeEnergyType, unit: .kilocalorie())
        let heartRate = await quantityAverage(workout: workout, embeddedType: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()))

        let distanceType = preferredDistanceType(for: workout.workoutActivityType)
        let distance = await quantitySum(workout: workout, embeddedType: distanceType, unit: .meter())

        return WorkoutSummary(
            energyKcal: energy,
            averageHeartRate: heartRate,
            distanceMeters: distance,
            sourceName: workout.sourceRevision.source.name
        )
    }

    private func preferredDistanceType(for activityType: HKWorkoutActivityType) -> HKQuantityType {
        activityType == .cycling ? distanceCyclingType : distanceWalkingRunningType
    }

    private func quantitySum(workout: HKWorkout, embeddedType: HKQuantityType, unit: HKUnit) async -> Double? {
        if let value = workout.statistics(for: embeddedType)?.sumQuantity()?.doubleValue(for: unit), value > 0 {
            return value
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: embeddedType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return total > 0 ? total : nil
    }

    private func quantityAverage(workout: HKWorkout, embeddedType: HKQuantityType, unit: HKUnit) async -> Double? {
        if let value = workout.statistics(for: embeddedType)?.averageQuantity()?.doubleValue(for: unit) {
            return value
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: embeddedType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: unit) }
        return total / Double(samples.count)
    }
}

public extension HKWorkoutActivityType {
    /// Ordnet einen HealthKit-Aktivitätstyp einer passenden Cardio-Übung aus
    /// `ExerciseLibrary` zu, damit deren Muskelgruppen (`primaryMuscles`/
    /// `secondaryMuscles`) für die Belastungsberechnung importierter
    /// Ausdauertrainings wiederverwendet werden können - `nil`, wenn der Typ
    /// keine verlässliche Muskelzuordnung erlaubt (z.B. reines Kraft-
    /// training ohne Satz-/Wiederholungsdaten in HealthKit).
    var cardioExerciseLibraryId: String? {
        switch self {
        case .running, .hiking: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .rowing: return "rowing-machine"
        case .jumpRope: return "jump-rope"
        case .stairClimbing: return "stair-climber"
        case .swimming: return "swimming"
        case .highIntensityIntervalTraining, .mixedCardio, .cardioDance: return "sprint-intervals"
        case .elliptical: return "elliptical"
        default: return nil
        }
    }

    /// Deutscher Anzeigename für die gängigsten Aktivitätstypen, für importierte
    /// HealthKit-Workouts ohne eigene FitTrack-Übungszuordnung.
    var displayName: String {
        switch self {
        case .running: return "Laufen"
        case .walking: return "Gehen"
        case .cycling: return "Radfahren"
        case .swimming: return "Schwimmen"
        case .hiking: return "Wandern"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Funktionelles Krafttraining"
        case .traditionalStrengthTraining: return "Krafttraining"
        case .coreTraining: return "Core-Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rudern"
        case .elliptical: return "Crosstrainer"
        case .stairClimbing: return "Treppensteigen"
        case .mixedCardio, .cardioDance: return "Cardio"
        case .dance: return "Tanzen"
        case .pilates: return "Pilates"
        case .climbing: return "Klettern"
        case .soccer: return "Fußball"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .other: return "Training"
        default: return "Training"
        }
    }
}

public enum HealthKitManagerError: Error {
    case workoutFinishFailed
}
