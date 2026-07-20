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
        // Vor der Volumen-Berechnung aktualisieren, da `muscleLoadEvents()`
        // synchron auf den (evtl. noch leeren) Cache zugreift - siehe
        // `BodyWeightCache`.
        await BodyWeightCache.shared.refresh()

        let events = sessions.flatMap { $0.muscleLoadEvents(maxHeartRate: maxHeartRate) }
        let statuses = MuscleLoadCalculator.status(for: events)
        let overall = MuscleLoadCalculator.overallLoad(from: statuses)

        // `sessionCount`/ACWR zählen weiterhin jede Einheit einzeln (auch
        // mehrere am selben Tag), da das für die langfristige 28-Tage-Basis
        // die richtige Auflösung ist. `sessionCount` steuert in RecoveryEngine,
        // ab wann zusätzlich die langfristige (ACWR-)Belastung einfließt.
        let sortedSessions = sessions.sorted { $0.date < $1.date }
        let sessionLoadsWithDates: [(date: Date, load: Double)] = sortedSessions.compactMap { session in
            let load = session.muscleLoadEvents(maxHeartRate: maxHeartRate).reduce(0.0) { $0 + $1.volume }
            return load > 0 ? (session.date, load) : nil
        }
        let sessionCount = sessionLoadsWithDates.count

        // `recentSessionLoad` (Teil der "Trainingslast" in RecoveryEngine)
        // summiert dagegen bewusst ALLE Einheiten desselben Kalendertags wie
        // die zuletzt protokollierte - z.B. Cardio morgens + Krafttraining
        // nachmittags zählen hier zusammen, statt dass nur die chronologisch
        // letzte Einheit berücksichtigt wird und die andere unter den Tisch fällt.
        let calendar = Calendar.current
        let mostRecentDate = sessionLoadsWithDates.last?.date
        let recentSessionLoad = mostRecentDate.map { recentDate in
            sessionLoadsWithDates
                .filter { calendar.isDate($0.date, inSameDayAs: recentDate) }
                .reduce(0.0) { $0 + $1.load }
        } ?? 0
        let daysSinceRecentSession = mostRecentDate.map { max(0, Date.now.timeIntervalSince($0) / 86400) }

        // Persönlicher Vergleichswert für `recentSessionLoad` (Median früherer
        // Einheiten, ohne den/die gerade betrachteten Tag) statt eines für
        // alle gleichen absoluten Richtwerts - sonst würde jemand, der
        // grundsätzlich mit geringerem Gewicht trainiert, bei einer für diese
        // Person tatsächlich harten Einheit trotzdem dauerhaft einen "alles
        // im grünen Bereich"-Wert sehen, nur weil die kg-Zahlen klein sind.
        // Median statt Mittelwert, damit ein einzelner sehr leichter/harter
        // Ausreißertag den Vergleichswert nicht verzerrt. Erst ab 5 früheren
        // Einheiten, davor ist kein verlässlicher eigener Durchschnitt bekannt.
        let priorSessionLoads: [Double] = mostRecentDate.map { recentDate in
            sessionLoadsWithDates.filter { !calendar.isDate($0.date, inSameDayAs: recentDate) }.map(\.load)
        } ?? []
        let personalTypicalSessionLoad: Double? = priorSessionLoads.count >= 5
            ? median(Array(priorSessionLoads.suffix(30)))
            : nil

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
            personalTypicalSessionLoad: personalTypicalSessionLoad,
            recentIntensity: recentIntensity
        )

        muscleStatuses = statuses
        readiness = RecoveryEngine.evaluate(inputs: inputs)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
