import Foundation
import FitTrackShared

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var readiness: ReadinessResult?
    @Published var muscleStatuses: [MuscleGroup: MuscleLoadStatus] = [:]
    @Published var isLoading = false

    func refresh(sessions: [WorkoutSession]) async {
        isLoading = true
        defer { isLoading = false }

        // Geschätzte HFmax (aus dem Geburtsdatum in Health, falls freigegeben)
        // macht die Herzfrequenz-Bewertung individuell statt gegen einen für
        // alle gleichen 130-bpm-Richtwert - siehe `intensityMultiplier`.
        let maxHeartRate = HealthKitManager.shared.fetchEstimatedMaxHeartRate()

        let events = sessions.flatMap { $0.muscleLoadEvents(maxHeartRate: maxHeartRate) }
        let statuses = MuscleLoadCalculator.status(for: events)
        let overall = MuscleLoadCalculator.overallLoad(from: statuses)

        // Belastung pro Trainingseinheit (nicht pro Kalendertag!) - zwei
        // Einheiten am selben Tag (z.B. beim Testen kurz hintereinander)
        // zählen als zwei eigene Einheiten, statt zu einem Tageswert zu
        // verschmelzen. `sessionCount` steuert in RecoveryEngine, ab wann
        // zusätzlich die langfristige (ACWR-)Belastung einfließt.
        let sortedSessions = sessions.sorted { $0.date < $1.date }
        let sessionLoadsWithDates: [(date: Date, load: Double)] = sortedSessions.compactMap { session in
            let load = session.muscleLoadEvents(maxHeartRate: maxHeartRate).reduce(0.0) { $0 + $1.volume }
            return load > 0 ? (session.date, load) : nil
        }
        let recentSessionLoad = sessionLoadsWithDates.last?.load ?? 0
        let daysSinceRecentSession = sessionLoadsWithDates.last.map { max(0, Date.now.timeIntervalSince($0.date) / 86400) }
        let sessionCount = sessionLoadsWithDates.count

        // Wahrgenommene Anstrengung (RPE/Trainings-Herzfrequenz) der letzten
        // ca. 2 Tage, neuere Einheiten stärker gewichtet - reagiert anders als
        // die beiden Werte oben sofort, auch ganz ohne Trainingshistorie.
        let now = Date.now
        let recentIntensitySamples: [(weight: Double, intensity: Double)] = sessions.compactMap { session in
            guard session.perceivedExertion != nil || session.averageHeartRate != nil else { return nil }
            let ageInDays = now.timeIntervalSince(session.date) / 86400
            guard ageInDays >= 0, ageInDays <= 2 else { return nil }
            return (max(0, 1 - ageInDays / 2), session.intensityMultiplier(maxHeartRate: maxHeartRate))
        }
        let recentIntensityWeight = recentIntensitySamples.reduce(0.0) { $0 + $1.weight }
        let recentIntensity: Double? = recentIntensityWeight > 0
            ? recentIntensitySamples.reduce(0.0) { $0 + $1.intensity * $1.weight } / recentIntensityWeight
            : nil

        async let sleepSummary = HealthKitManager.shared.fetchLastNightSleep()
        async let hrvValue = HealthKitManager.shared.fetchLatestHRV()
        async let hrvBaselineValue = HealthKitManager.shared.fetchHRVBaseline()
        async let rhrValue = HealthKitManager.shared.fetchLatestRestingHeartRate()
        async let rhrBaselineValue = HealthKitManager.shared.fetchRestingHeartRateBaseline()

        let sleep = await sleepSummary
        let hrv = await hrvValue
        let hrvBaseline = await hrvBaselineValue
        let rhr = await rhrValue
        let rhrBaseline = await rhrBaselineValue

        let inputs = RecoveryInputs(
            sleepHours: sleep?.asleepHours,
            sleepEfficiency: sleep?.efficiency,
            hrvMs: hrv,
            hrvBaselineMs: hrvBaseline,
            restingHeartRate: rhr,
            restingHeartRateBaseline: rhrBaseline,
            acuteLoad: overall.acute,
            chronicLoad: overall.chronic,
            sessionCount: sessionCount,
            recentSessionLoad: recentSessionLoad,
            daysSinceRecentSession: daysSinceRecentSession,
            recentIntensity: recentIntensity
        )

        muscleStatuses = statuses
        readiness = RecoveryEngine.evaluate(inputs: inputs)
    }
}
