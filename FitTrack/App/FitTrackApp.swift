import SwiftUI
import SwiftData

@main
struct FitTrackApp: App {
    let modelContainer: ModelContainer = FitTrackApp.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }

    /// Baut den SwiftData-Container auf. Schlägt die automatische Migration
    /// eines bereits vorhandenen Stores fehl (z.B. nach einer Änderung am
    /// Datenmodell), wird der alte Store verworfen und ein frischer angelegt,
    /// statt die App beim Start mit einem schwarzen Bildschirm abstürzen zu lassen.
    ///
    /// Bewusst EIN einzelner, unbenannter Store (wie von Anfang an) statt
    /// mehrerer benannter Konfigurationen für einen möglichen iCloud-Sync der
    /// Pläne: benannte Konfigurationen landen an einem anderen Speicherort und
    /// hätten sonst alle bereits vorhandenen Pläne/Trainings "unsichtbar"
    /// gemacht. iCloud-Sync ist mit dem aktuellen (kostenlosen) Apple-Account
    /// ohnehin nicht möglich (siehe Gespräch) - die Modelle (`TrainingPlan`,
    /// `PlanDay`, `PlanItem`) bleiben aber CloudKit-vorbereitet, falls das
    /// später via eines bezahlten Developer-Accounts sauber nachgezogen wird.
    private static func makeModelContainer() -> ModelContainer {
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
}
