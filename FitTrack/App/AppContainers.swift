import SwiftData

/// Referenzen auf die beiden SwiftData-Container der App, gesetzt einmalig
/// beim Start (`FitTrackApp.init`). Pläne haben einen eigenen, über iCloud
/// synchronisierten Container; alles andere (Trainings-Verlauf) bleibt im
/// lokalen `history`-Container. `ActiveWorkoutView` braucht explizit Zugriff
/// auf beide gleichzeitig (Training speichern = history, Plan-Gedächtnis
/// aktualisieren = plans) - da SwiftUIs `@Environment(\.modelContext)` immer
/// nur den zuletzt via `.modelContainer(...)` angehängten Container liefert,
/// wird der jeweils "fremde" Container hier explizit gehalten, statt über die
/// Umgebung durchgereicht zu werden.
enum AppContainers {
    static var history: ModelContainer!
    static var plans: ModelContainer!
}
