import SwiftUI
import SwiftData
import HealthKit
import FitTrackShared

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Übersicht", systemImage: "heart.text.square") }

            ExerciseLibraryView()
                .tabItem { Label("Übungen", systemImage: "figure.strengthtraining.traditional") }

            TrainingPlansView()
                .tabItem { Label("Pläne", systemImage: "list.bullet.clipboard") }

            WorkoutHistoryView()
                .tabItem { Label("Verlauf", systemImage: "clock.arrow.circlepath") }
        }
        .task {
            connectivity.activate()
            try? await HealthKitManager.shared.requestAuthorization()
        }
        .onChange(of: connectivity.receivedCompletedWorkout) { _, newValue in
            guard let dto = newValue else { return }
            Task { await importCompletedWorkout(dto) }
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
    }
}
