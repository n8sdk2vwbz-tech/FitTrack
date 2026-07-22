import SwiftUI
import SwiftData
import HealthKit
import UserNotifications
import FitTrackShared

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var pendingSharedPlan: SharedPlanDTO?
    /// Muss der Watch nach der Aktivierung einmalig mitgeteilt werden (siehe
    /// `WatchConnectivityManager.sendRestTimerPreference`), sonst kennt ein
    /// direkt auf der Watch gestartetes Training die Einstellung nicht, bevor
    /// sie das erste Mal in den Einstellungen geändert wurde.
    @AppStorage("restTimerEnabled") private var restTimerEnabled = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Übersicht", systemImage: "heart.text.square") }

            ExerciseLibraryView()
                .tabItem { Label("Übungen", systemImage: "figure.strengthtraining.traditional") }

            TrainingPlansView()
                .modelContainer(AppContainers.plans)
                .tabItem { Label("Pläne", systemImage: "list.bullet.clipboard") }

            WorkoutHistoryView()
                .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
        }
        .task {
            connectivity.activate()
            connectivity.sendRestTimerPreference(restTimerEnabled)
            try? await HealthKitManager.shared.requestAuthorization()
            // Für die Satzpausen-Mitteilung (siehe `ActiveWorkoutView.
            // notifyRestComplete`) - still im Hintergrund angefragt, kein
            // Abbruch der App falls abgelehnt.
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        .onChange(of: connectivity.receivedCompletedWorkout) { _, newValue in
            guard let dto = newValue else { return }
            Task { await importCompletedWorkout(dto) }
        }
        .onOpenURL { url in
            pendingSharedPlan = PlanSharePayload.decode(from: url)
        }
        .sheet(item: $pendingSharedPlan) { sharedPlan in
            ImportPlanView(sharedPlan: sharedPlan)
        }
    }

    /// Übernimmt ein von der Watch abgeschlossenes Workout in den lokalen
    /// SwiftData-Store und speichert die Zusammenfassung zusätzlich in HealthKit.
    private func importCompletedWorkout(_ dto: CompletedWorkoutDTO) async {
        let entries = dto.exercises.enumerated().map { index, exercise -> ExerciseEntry in
            let sets = exercise.sets.map { SetEntry(reps: $0.reps, weightKg: $0.weightKg, isWarmup: $0.isWarmup) }
            return ExerciseEntry(exerciseId: exercise.exerciseId, exerciseName: exercise.exerciseName, order: index, sets: sets)
        }

        let session = WorkoutSession(
            id: dto.id,
            date: dto.startDate,
            activityName: dto.activityName,
            durationSeconds: dto.endDate.timeIntervalSince(dto.startDate),
            totalEnergyBurnedKcal: dto.totalEnergyBurnedKcal,
            averageHeartRate: dto.averageHeartRate,
            source: .watch,
            healthKitWorkoutUUID: dto.healthKitWorkoutUUID,
            entries: entries
        )
        modelContext.insert(session)
        try? modelContext.save()

        if dto.healthKitWorkoutUUID == nil {
            _ = try? await HealthKitManager.shared.saveWorkout(
                activityType: .traditionalStrengthTraining,
                start: dto.startDate,
                end: dto.endDate,
                totalEnergyBurnedKcal: dto.totalEnergyBurnedKcal,
                averageHeartRate: dto.averageHeartRate
            )
        }
        await StravaManager.shared.autoUploadIfNeeded(session: session)
    }
}
