import Foundation
import SwiftData
import FitTrackShared

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var readiness: ReadinessResult?
    @Published var muscleStatuses: [MuscleGroup: MuscleLoadStatus] = [:]
    @Published var isLoading = false

    func refresh(sessions: [WorkoutSession], modelContext: ModelContext) async {
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
        // summiert ALLE Einheiten der letzten `recentSessionLoadFadeDays` Tage,
        // jede einzeln nach ihrem eigenen Alter linear abklingend gewichtet -
        // z.B. Cardio morgens + Krafttraining nachmittags zählen am selben Tag
        // voll zusammen, und ein hartes Training von vor 2 Tagen trägt noch
        // spürbar (nur etwas abgeschwächt) bei, statt beim Hinzukommen einer
        // neueren Einheit (z.B. eines Laufs) schlagartig komplett zu
        // verschwinden - echter Muskelkater hält schließlich auch mehrere
        // Tage an, nicht nur bis zur nächsten protokollierten Einheit.
        let calendar = Calendar.current
        let mostRecentDate = sessionLoadsWithDates.last?.date
        let fadeDays = RecoveryEngine.recentSessionLoadFadeDays
        let now = Date.now
        let recentSessionLoad = sessionLoadsWithDates.reduce(0.0) { total, entry in
            let ageInDays = max(0, now.timeIntervalSince(entry.date) / 86400)
            guard ageInDays <= fadeDays else { return total }
            let decay = max(0, 1 - ageInDays / fadeDays)
            return total + entry.load * decay
        }
        let daysSinceRecentSession = mostRecentDate.map { max(0, now.timeIntervalSince($0) / 86400) }

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
        // Tage (dasselbe Zeitfenster wie `recentSessionLoad`), neuere
        // Einheiten stärker gewichtet - reagiert anders als die beiden Werte
        // oben sofort, auch ganz ohne Trainingshistorie. War vorher auf 2 Tage
        // begrenzt - dadurch war bei einem Trainingsabstand von z.B. 1,8
        // Tagen (wie bei echtem Muskelkater üblich) schon fast nichts mehr
        // von der Anstrengung übrig.
        let recentIntensitySamples: [(weight: Double, intensity: Double)] = sessions.compactMap { session in
            guard session.perceivedExertion != nil || session.averageHeartRate != nil else { return nil }
            let ageInDays = now.timeIntervalSince(session.date) / 86400
            guard ageInDays >= 0, ageInDays <= fadeDays else { return nil }
            return (max(0, 1 - ageInDays / fadeDays), session.intensityMultiplier(maxHeartRate: maxHeartRate))
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
        let result = RecoveryEngine.evaluate(inputs: inputs)
        readiness = result
        saveSnapshot(result, modelContext: modelContext)
    }

    /// Sichert den heutigen Bereitschafts-Score dauerhaft (siehe
    /// `DailyReadinessSnapshot`) - höchstens ein Eintrag pro Kalendertag,
    /// spätere Aufrufe am selben Tag aktualisieren nur den bestehenden.
    private func saveSnapshot(_ result: ReadinessResult, modelContext: ModelContext) {
        let day = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DailyReadinessSnapshot>(predicate: #Predicate { $0.day == day })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(with: result)
        } else {
            modelContext.insert(DailyReadinessSnapshot(
                day: day,
                score: result.score,
                category: result.category,
                sleepScore: result.sleepScore,
                hrvScore: result.hrvScore,
                rhrScore: result.rhrScore,
                trainingLoadScore: result.trainingLoadScore,
                sleepHours: result.sleepHours,
                hrvMs: result.hrvMs,
                hrvBaselineMs: result.hrvBaselineMs,
                restingHeartRate: result.restingHeartRate,
                restingHeartRateBaseline: result.restingHeartRateBaseline
            ))
        }
        try? modelContext.save()
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
