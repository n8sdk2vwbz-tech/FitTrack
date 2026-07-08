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

    /// Trainings-Verlauf (und, aus Kompatibilitätsgründen, weiterhin auch die
    /// Plan-Modelltypen im Schema - siehe `migratePlansIfNeeded`) bleibt exakt
    /// im ursprünglichen, unbenannten lokalen Store wie von Anfang an. Schlägt
    /// die automatische Migration eines bereits vorhandenen Stores fehl (z.B.
    /// nach einer Änderung am Datenmodell), wird der alte Store verworfen und
    /// ein frischer angelegt, statt die App beim Start mit einem schwarzen
    /// Bildschirm abstürzen zu lassen.
    private static func makeHistoryContainer() -> ModelContainer {
        let schema = Schema([
            WorkoutSession.self,
            ExerciseEntry.self,
            SetEntry.self,
            TrainingPlan.self,
            PlanDay.self,
            PlanItem.self
        ])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        let url = configuration.url
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }

        guard let recreatedContainer = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("FitTrack: SwiftData-Container konnte auch nach dem Zurücksetzen des lokalen Speichers nicht erstellt werden.")
        }
        return recreatedContainer
    }

    /// Eigener Container nur für Trainingspläne, über iCloud (private
    /// Datenbank) synchronisiert, damit sie auf allen Geräten mit demselben
    /// Apple-Account verfügbar sind. Fällt automatisch auf einen rein lokalen
    /// Container zurück, falls iCloud gerade nicht verfügbar ist (kein
    /// Account, Entitlement nicht provisioniert, ...), statt die App
    /// abstürzen zu lassen.
    private static func makePlansContainer() -> ModelContainer {
        let schema = Schema([TrainingPlan.self, PlanDay.self, PlanItem.self])

        let cloudConfiguration = ModelConfiguration("PlansCloudKit", schema: schema, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            return container
        }

        let localConfiguration = ModelConfiguration("PlansCloudKit", schema: schema, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: [localConfiguration]) {
            return container
        }

        let url = localConfiguration.url
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
        guard let recreatedContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
            fatalError("FitTrack: Plans-Container konnte auch nach dem Zurücksetzen nicht erstellt werden.")
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
