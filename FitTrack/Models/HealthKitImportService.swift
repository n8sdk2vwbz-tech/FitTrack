import Foundation
import SwiftData
import FitTrackShared

/// Importiert Workouts aus HealthKit, die eine andere App aufgezeichnet hat
/// (z.B. die native Apple Watch Workout-App oder Strava), als `WorkoutSession`
/// in FitTrack - analog zu Stravas automatischem Health-Import. So müssen
/// Cardio-Einheiten wie Laufen oder Radfahren nicht in FitTrack selbst
/// gestartet werden, sondern erscheinen automatisch im Verlauf.
enum HealthKitImportService {

    static func importNewWorkouts(daysBack: Int = 90, existingSessions: [WorkoutSession], modelContext: ModelContext) async {
        let hkWorkouts = await HealthKitManager.shared.fetchRecentWorkouts(daysBack: daysBack)

        // Abgleich: Wurde ein importiertes Workout direkt in Apple Health
        // gelöscht (statt in FitTrack), existiert seine UUID nicht mehr in den
        // aktuellen HealthKit-Ergebnissen - die lokale Kopie dann ebenfalls
        // entfernen. Nur innerhalb des abgefragten Zeitraums prüfen, damit
        // ältere, außerhalb des Fensters liegende Importe nicht fälschlich
        // gelöscht werden.
        let currentHealthUUIDs = Set(hkWorkouts.map { $0.uuid.uuidString })
        var didChange = false
        if let windowStart = Calendar.current.date(byAdding: .day, value: -daysBack, to: .now) {
            for session in existingSessions where session.source == .health && session.date >= windowStart {
                if let uuid = session.healthKitWorkoutUUID, !currentHealthUUIDs.contains(uuid) {
                    modelContext.delete(session)
                    didChange = true
                }
            }
        }

        let knownUUIDs = Set(existingSessions.compactMap(\.healthKitWorkoutUUID))
        let localSessions = existingSessions.filter { $0.source != .health }

        let newWorkouts = hkWorkouts.filter { workout in
            if knownUUIDs.contains(workout.uuid.uuidString) { return false }
            // Vom Nutzer bewusst gelöschte Workouts nicht erneut importieren.
            if DismissedHealthKitWorkouts.isDismissed(workout.uuid.uuidString) { return false }
            // Heuristische Dublettenprüfung für den seltenen Fall, dass ein per
            // Watch ferngesteuertes Training seine HealthKit-UUID nicht mehr
            // rechtzeitig ans iPhone zurückgemeldet hat.
            let isLikelyDuplicate = localSessions.contains { session in
                abs(session.date.timeIntervalSince(workout.startDate)) < 120
            }
            return !isLikelyDuplicate
        }

        for workout in newWorkouts {
            let summary = await HealthKitManager.shared.summary(for: workout)
            let session = WorkoutSession(
                date: workout.startDate,
                activityName: workout.workoutActivityType.displayName,
                durationSeconds: workout.duration,
                totalEnergyBurnedKcal: summary.energyKcal,
                averageHeartRate: summary.averageHeartRate,
                distanceMeters: summary.distanceMeters,
                externalSourceName: summary.sourceName,
                source: .health,
                healthKitWorkoutUUID: workout.uuid.uuidString
            )
            modelContext.insert(session)
            didChange = true
        }

        if didChange {
            try? modelContext.save()
        }
    }
}

/// Merkt sich HealthKit-Workout-UUIDs, die der Nutzer bewusst aus FitTrack
/// gelöscht hat, damit `HealthKitImportService` sie beim nächsten Import
/// nicht wieder aus Apple Health hereinzieht.
enum DismissedHealthKitWorkouts {
    private static let key = "dismissedHealthKitWorkoutUUIDs"

    static func isDismissed(_ uuid: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(uuid)
    }

    static func markDismissed(_ uuid: String) {
        var set = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        set.insert(uuid)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
