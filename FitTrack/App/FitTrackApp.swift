import SwiftUI
import SwiftData

@main
struct FitTrackApp: App {
    let historyContainer: ModelContainer
    let plansContainer: ModelContainer

    init() {
        let history = FitTrackApp.makeHistoryContainer()
        let plans = FitTrackApp.makePlansContainer()
        historyContainer = history
        plansContainer = plans
        AppContainers.history = history
        AppContainers.plans = plans
        FitTrackApp.migratePlansIfNeeded(from: history, to: plans)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(historyContainer)
    }

    private static let historySchema = Schema([
        WorkoutSession.self,
        ExerciseEntry.self,
        SetEntry.self,
        TrainingPlan.self,
        PlanDay.self,
        PlanItem.self
    ])

    private static let plansSchema = Schema([TrainingPlan.self, PlanDay.self, PlanItem.self])

    /// `SwiftDataError` liefert über seine reine Textbeschreibung hinaus fast
    /// nie Details (meist `_explanation: nil`) - der eigentliche Grund steckt
    /// oft in der als NSError gebridgten `userInfo`/`NSUnderlyingErrorKey`.
    /// Nur zu Diagnosezwecken beim lokalen Debug-Start gedacht.
    private static func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(error)", "domain=\(nsError.domain)", "code=\(nsError.code)"]
        if !nsError.userInfo.isEmpty {
            parts.append("userInfo=\(nsError.userInfo)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying)")
        }
        return parts.joined(separator: " || ")
    }

    /// Trainings-Verlauf (und, aus Kompatibilitätsgründen, weiterhin auch die
    /// Plan-Modelltypen im Schema - siehe `migratePlansIfNeeded`), im
    /// ursprünglichen, unbenannten Store wie von Anfang an - jetzt aber über
    /// iCloud (private Datenbank) synchronisiert, damit ein Neuinstallieren
    /// der App nicht mehr Sätze/Gewichte und die daraus berechnete
    /// Trainingslast unwiderruflich löscht. Wichtig: das CloudKit-Schema muss
    /// nach jeder Modelländerung zusätzlich manuell in der CloudKit-Konsole
    /// von Development nach Production übertragen werden - sonst syncen
    /// TestFlight-/App-Store-Builds trotz korrekter Konfiguration nicht.
    private static func makeHistoryContainer() -> ModelContainer {
        let cloudConfiguration = ModelConfiguration(schema: historySchema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: historySchema, configurations: [cloudConfiguration])
        } catch {
            print("FitTrack: History-CloudKit-Container beim ersten Versuch nicht ladbar (\(describeError(error))) - versuche Selbstheilung.")
        }

        // Scheitert typischerweise, weil an dieser Stelle bereits ein rein
        // lokaler Store liegt (aus der Zeit vor dieser CloudKit-Umstellung,
        // oder von einem früheren Lauf, in dem iCloud nicht verfügbar war) -
        // SwiftData kann so einen Store nicht "in place" auf CloudKit
        // umstellen, das Laden scheitert dann mit einem generischen Fehler.
        // Vorhandene Trainings (UND ggf. noch nicht migrierte Pläne, siehe
        // `migratePlansIfNeeded`) deshalb zuerst auslesen, den alten Store
        // löschen und frisch mit CloudKit-Unterstützung anlegen, die
        // Datensätze zurückkopieren - statt sie beim Umstieg zu verlieren.
        let localConfiguration = ModelConfiguration(schema: historySchema, cloudKitDatabase: .none)
        var existingSessions: [WorkoutSessionSnapshot] = []
        var existingPlans: [TrainingPlanSnapshot] = []
        do {
            let oldContainer = try ModelContainer(for: historySchema, configurations: [localConfiguration])
            let oldContext = ModelContext(oldContainer)
            existingSessions = ((try? oldContext.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map(WorkoutSessionSnapshot.init)
            existingPlans = ((try? oldContext.fetch(FetchDescriptor<TrainingPlan>())) ?? []).map(TrainingPlanSnapshot.init)
            print("FitTrack: History - alter lokaler Store gefunden, \(existingSessions.count) Training(s)/\(existingPlans.count) Plan(-Objekt) werden übernommen.")
        } catch {
            print("FitTrack: History - kein vorhandener lokaler Store zum Übernehmen gefunden (\(error)).")
        }

        let url = localConfiguration.url
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }

        do {
            let freshContainer = try ModelContainer(for: historySchema, configurations: [cloudConfiguration])
            print("FitTrack: History-CloudKit-Container nach Zurücksetzen erfolgreich neu erstellt.")
            if !existingSessions.isEmpty || !existingPlans.isEmpty {
                let context = ModelContext(freshContainer)
                for snapshot in existingSessions { context.insert(snapshot.makeSession()) }
                for snapshot in existingPlans { context.insert(snapshot.makePlan()) }
                try? context.save()
            }
            return freshContainer
        } catch {
            print("FitTrack: History-CloudKit-Container konnte auch nach Zurücksetzen nicht erstellt werden (\(describeError(error))) - falle auf rein lokalen Speicher zurück.")
        }

        // iCloud offenbar nicht verfügbar (kein Account, Entitlement nicht
        // provisioniert, ...) - rein lokal weitermachen, statt die App
        // abstürzen zu lassen.
        guard let recreatedContainer = try? ModelContainer(for: historySchema, configurations: [localConfiguration]) else {
            fatalError("FitTrack: SwiftData-Container konnte auch nach dem Zurücksetzen des lokalen Speichers nicht erstellt werden.")
        }
        if !existingSessions.isEmpty || !existingPlans.isEmpty {
            let context = ModelContext(recreatedContainer)
            for snapshot in existingSessions { context.insert(snapshot.makeSession()) }
            for snapshot in existingPlans { context.insert(snapshot.makePlan()) }
            try? context.save()
        }
        return recreatedContainer
    }

    /// Eigener Container nur für Trainingspläne, über iCloud (private
    /// Datenbank) synchronisiert, damit sie auf allen Geräten mit demselben
    /// Apple-Account verfügbar sind. Fällt automatisch auf einen rein lokalen
    /// Container zurück, falls iCloud gerade nicht verfügbar ist (kein
    /// Account, Entitlement nicht provisioniert, ...), statt die App
    /// abstürzen zu lassen. Dieselbe Migrations-Logik wie in
    /// `makeHistoryContainer`, falls unter diesem Namen bereits ein rein
    /// lokaler Store existiert (z.B. weil CloudKit bei einem früheren Lauf
    /// nicht verfügbar war und die App seitdem lokal weitergelaufen ist).
    private static func makePlansContainer() -> ModelContainer {
        let cloudConfiguration = ModelConfiguration("PlansCloudKit", schema: plansSchema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: plansSchema, configurations: [cloudConfiguration])
        } catch {
            print("FitTrack: Plans-CloudKit-Container beim ersten Versuch nicht ladbar (\(describeError(error))) - versuche Selbstheilung.")
        }

        let localConfiguration = ModelConfiguration("PlansCloudKit", schema: plansSchema, cloudKitDatabase: .none)
        var existingPlans: [TrainingPlanSnapshot] = []
        do {
            let oldContainer = try ModelContainer(for: plansSchema, configurations: [localConfiguration])
            let oldContext = ModelContext(oldContainer)
            existingPlans = ((try? oldContext.fetch(FetchDescriptor<TrainingPlan>())) ?? []).map(TrainingPlanSnapshot.init)
            print("FitTrack: Plans - alter lokaler Store gefunden, \(existingPlans.count) Plan(-Objekt) werden übernommen.")
        } catch {
            print("FitTrack: Plans - kein vorhandener lokaler Store zum Übernehmen gefunden (\(error)).")
        }

        let url = localConfiguration.url
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }

        do {
            let freshContainer = try ModelContainer(for: plansSchema, configurations: [cloudConfiguration])
            print("FitTrack: Plans-CloudKit-Container nach Zurücksetzen erfolgreich neu erstellt.")
            if !existingPlans.isEmpty {
                let context = ModelContext(freshContainer)
                for snapshot in existingPlans { context.insert(snapshot.makePlan()) }
                try? context.save()
            }
            return freshContainer
        } catch {
            print("FitTrack: Plans-CloudKit-Container konnte auch nach Zurücksetzen nicht erstellt werden (\(describeError(error))) - falle auf rein lokalen Speicher zurück.")
        }

        guard let recreatedContainer = try? ModelContainer(for: plansSchema, configurations: [localConfiguration]) else {
            fatalError("FitTrack: Plans-Container konnte auch nach dem Zurücksetzen nicht erstellt werden.")
        }
        if !existingPlans.isEmpty {
            let context = ModelContext(recreatedContainer)
            for snapshot in existingPlans { context.insert(snapshot.makePlan()) }
            try? context.save()
        }
        return recreatedContainer
    }

    /// Einmalige Übernahme bereits vorhandener Pläne aus dem alten,
    /// gemeinsamen Store in den neuen, eigenständigen (iCloud-fähigen)
    /// Plans-Container. Ohne diesen Schritt wären alle vor diesem Update
    /// angelegten Pläne für die App unsichtbar, weil sie ab jetzt nur noch im
    /// neuen Container gesucht werden - das ist genau der Fehler, der beim
    /// ersten (zurückgenommenen) iCloud-Versuch passiert ist. Läuft nur
    /// einmal (Flag in UserDefaults), da die alten Pläne danach aus dem
    /// History-Store entfernt werden, um keine Duplikate vorzuhalten.
    private static func migratePlansIfNeeded(from history: ModelContainer, to plans: ModelContainer) {
        let migrationKey = "didMigratePlansToCloudKitContainer"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let oldContext = ModelContext(history)
        guard let oldPlans = try? oldContext.fetch(FetchDescriptor<TrainingPlan>()), !oldPlans.isEmpty else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        let newContext = ModelContext(plans)
        for oldPlan in oldPlans {
            let newPlan = TrainingPlan(id: oldPlan.id, name: oldPlan.name, notes: oldPlan.notes, createdAt: oldPlan.createdAt)
            for oldDay in oldPlan.dayList.sorted(by: { $0.order < $1.order }) {
                let newDay = PlanDay(name: oldDay.name, order: oldDay.order)
                for oldItem in oldDay.itemList.sorted(by: { $0.order < $1.order }) {
                    newDay.itemList.append(PlanItem(
                        exerciseId: oldItem.exerciseId,
                        exerciseName: oldItem.exerciseName,
                        targetSets: oldItem.targetSets,
                        targetReps: oldItem.targetReps,
                        targetWeightKg: oldItem.targetWeightKg,
                        warmupSetCount: oldItem.warmupSetCount,
                        order: oldItem.order
                    ))
                }
                newPlan.dayList.append(newDay)
            }
            newContext.insert(newPlan)
        }

        guard (try? newContext.save()) != nil else {
            // Übernahme fehlgeschlagen - alte Pläne NICHT löschen, Migration
            // beim nächsten Start erneut versuchen.
            return
        }

        for oldPlan in oldPlans {
            oldContext.delete(oldPlan)
        }
        try? oldContext.save()

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}

// MARK: - Snapshots für die CloudKit-Umstellung

/// Reine Werttypen (unabhängig vom ursprünglichen `ModelContext`), um
/// vorhandene Datensätze aus einem alten, rein lokalen Store auszulesen,
/// bevor dieser gelöscht wird, und sie danach in einen frisch angelegten
/// CloudKit-Store zurückzukopieren (siehe `FitTrackApp.makeHistoryContainer`/
/// `makePlansContainer`). `@Model`-Instanzen selbst gehören fest zu ihrem
/// Context und können nicht direkt in einen anderen übernommen werden.

private struct SetEntrySnapshot {
    let reps: Int
    let weightKg: Double
    let rpe: Double?
    let isWarmup: Bool
    let order: Int

    init(_ set: SetEntry) {
        reps = set.reps
        weightKg = set.weightKg
        rpe = set.rpe
        isWarmup = set.isWarmup
        order = set.order
    }

    func makeSetEntry() -> SetEntry {
        SetEntry(reps: reps, weightKg: weightKg, rpe: rpe, isWarmup: isWarmup, order: order)
    }
}

private struct ExerciseEntrySnapshot {
    let exerciseId: String
    let exerciseName: String
    let order: Int
    let sets: [SetEntrySnapshot]

    init(_ entry: ExerciseEntry) {
        exerciseId = entry.exerciseId
        exerciseName = entry.exerciseName
        order = entry.order
        sets = entry.setList.map(SetEntrySnapshot.init)
    }

    func makeExerciseEntry() -> ExerciseEntry {
        ExerciseEntry(exerciseId: exerciseId, exerciseName: exerciseName, order: order, sets: sets.map { $0.makeSetEntry() })
    }
}

private struct WorkoutSessionSnapshot {
    let id: String
    let date: Date
    let activityName: String
    let durationSeconds: Double
    let totalEnergyBurnedKcal: Double?
    let averageHeartRate: Double?
    let distanceMeters: Double?
    let externalSourceName: String?
    let source: WorkoutSource
    let healthKitWorkoutUUID: String?
    let healthKitActivityTypeRawValue: Int?
    let perceivedExertion: Int?
    let entries: [ExerciseEntrySnapshot]

    init(_ session: WorkoutSession) {
        id = session.id
        date = session.date
        activityName = session.activityName
        durationSeconds = session.durationSeconds
        totalEnergyBurnedKcal = session.totalEnergyBurnedKcal
        averageHeartRate = session.averageHeartRate
        distanceMeters = session.distanceMeters
        externalSourceName = session.externalSourceName
        source = session.source
        healthKitWorkoutUUID = session.healthKitWorkoutUUID
        healthKitActivityTypeRawValue = session.healthKitActivityTypeRawValue
        perceivedExertion = session.perceivedExertion
        entries = session.entryList.map(ExerciseEntrySnapshot.init)
    }

    func makeSession() -> WorkoutSession {
        WorkoutSession(
            id: id,
            date: date,
            activityName: activityName,
            durationSeconds: durationSeconds,
            totalEnergyBurnedKcal: totalEnergyBurnedKcal,
            averageHeartRate: averageHeartRate,
            distanceMeters: distanceMeters,
            externalSourceName: externalSourceName,
            source: source,
            healthKitWorkoutUUID: healthKitWorkoutUUID,
            healthKitActivityTypeRawValue: healthKitActivityTypeRawValue,
            perceivedExertion: perceivedExertion,
            entries: entries.map { $0.makeExerciseEntry() }
        )
    }
}

private struct PlanItemSnapshot {
    let exerciseId: String
    let exerciseName: String
    let targetSets: Int
    let targetReps: Int
    let targetWeightKg: Double?
    let warmupSetCount: Int
    let order: Int
    let alternativeExerciseIds: [String]
    let alternativeExerciseNames: [String]
    let notes: String
    let pendingWeightIncrease: Bool

    init(_ item: PlanItem) {
        exerciseId = item.exerciseId
        exerciseName = item.exerciseName
        targetSets = item.targetSets
        targetReps = item.targetReps
        targetWeightKg = item.targetWeightKg
        warmupSetCount = item.warmupSetCount
        order = item.order
        alternativeExerciseIds = item.alternativeExerciseIds
        alternativeExerciseNames = item.alternativeExerciseNames
        notes = item.notes
        pendingWeightIncrease = item.pendingWeightIncrease
    }

    func makeItem() -> PlanItem {
        PlanItem(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeightKg: targetWeightKg,
            warmupSetCount: warmupSetCount,
            order: order,
            alternativeExerciseIds: alternativeExerciseIds,
            alternativeExerciseNames: alternativeExerciseNames,
            notes: notes,
            pendingWeightIncrease: pendingWeightIncrease
        )
    }
}

private struct PlanDaySnapshot {
    let name: String
    let order: Int
    let items: [PlanItemSnapshot]

    init(_ day: PlanDay) {
        name = day.name
        order = day.order
        items = day.itemList.map(PlanItemSnapshot.init)
    }

    func makeDay() -> PlanDay {
        PlanDay(name: name, order: order, items: items.map { $0.makeItem() })
    }
}

private struct TrainingPlanSnapshot {
    let id: String
    let name: String
    let notes: String
    let createdAt: Date
    let days: [PlanDaySnapshot]

    init(_ plan: TrainingPlan) {
        id = plan.id
        name = plan.name
        notes = plan.notes
        createdAt = plan.createdAt
        days = plan.dayList.map(PlanDaySnapshot.init)
    }

    func makePlan() -> TrainingPlan {
        TrainingPlan(id: id, name: name, notes: notes, createdAt: createdAt, days: days.map { $0.makeDay() })
    }
}
