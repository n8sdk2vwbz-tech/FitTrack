import Foundation
import HealthKit
import Combine
import FitTrackShared

private struct DraftSet {
    var reps: Int
    var weightKg: Double
}

/// Steuert ein eigenständiges Watch-Workout über `HKWorkoutSession` /
/// `HKLiveWorkoutBuilder`. Läuft unabhängig vom iPhone (Watch-only), sendet
/// das Ergebnis am Ende per WatchConnectivity zurück.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {

    /// Singleton, damit `WatchAppDelegate.handle(_:)` (ausgelöst durch
    /// `HKHealthStore.startWatchApp(with:)` vom iPhone, außerhalb der
    /// SwiftUI-View-Hierarchie) dieselbe Instanz wie die App-Views erreicht.
    static let shared = WorkoutManager()

    @Published var heartRate: Double = 0
    @Published var activeEnergyKcal: Double = 0
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var sessionState: HKWorkoutSessionState = .notStarted
    @Published var currentExerciseIndex: Int = 0
    @Published var currentSetCount: Int = 0
    @Published var didFinish: Bool = false
    @Published var lastSummary: CompletedWorkoutDTO?
    /// true, wenn dieses Workout vom iPhone aus ferngesteuert gestartet wurde
    /// (die Watch dient dann nur als Sensor für die Herzfrequenz).
    @Published var isRemoteControlled: Bool = false
    @Published var remoteActivityName: String?

    var planDay: PlanDayDTO?

    private let healthStore = HealthKitManager.shared.healthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var timer: Timer?
    private var loggedSets: [Int: [DraftSet]] = [:] // planItem index -> sets
    private var averageHeartRateAtEnd: Double?
    private var remoteSessionId: String?
    private var pendingRemoteSessionTimeoutTask: Task<Void, Never>?
    private var unreachableTimeoutTask: Task<Void, Never>?
    private var reachabilityCancellable: AnyCancellable?

    /// Wie lange das iPhone nicht erreichbar sein darf, bevor eine
    /// ferngesteuerte Session selbst beendet wird (siehe `handleReachabilityChange`).
    private let unreachableTimeoutSeconds: UInt64 = 30
    /// Absolute Obergrenze für eine ferngesteuerte Session, unabhängig von der
    /// Erreichbarkeit - deckt den Fall ab, dass das iPhone zwar verbunden
    /// bleibt (z.B. App im Hintergrund weiterhin aktiv), aber nie explizit
    /// "Beenden" gesendet hat. Ohne dieses zweite, unabhängige Sicherheitsnetz
    /// könnte eine Session sonst unbegrenzt "aktiv" bleiben, obwohl real
    /// längst kein Training mehr stattfindet.
    private let maxRemoteSessionDuration: TimeInterval = 60 * 60

    var currentPlanItem: PlanItemDTO? {
        guard let planDay, planDay.items.indices.contains(currentExerciseIndex) else { return nil }
        return planDay.items[currentExerciseIndex]
    }

    override init() {
        super.init()
        // Sicherheitsnetz gegen für immer hängende ferngesteuerte Sessions:
        // wird der eigentliche Stop-Befehl vom iPhone NIE gesendet (z.B. weil
        // die App dort einfach beendet/abgeschossen statt ordentlich beendet
        // wurde), bliebe die Watch sonst dauerhaft "im Training" - Bildschirm
        // dimmt nicht mehr normal, App kehrt nie zum Zifferblatt zurück. Ist
        // das iPhone länger als `unreachableTimeoutSeconds` nicht erreichbar,
        // während wir fernsteuert werden, beenden wir die Session selbst.
        reachabilityCancellable = WatchConnectivityManager.shared.$isCounterpartReachable
            .sink { [weak self] reachable in
                Task { @MainActor in
                    self?.handleReachabilityChange(reachable)
                }
            }
    }

    private func handleReachabilityChange(_ reachable: Bool) {
        unreachableTimeoutTask?.cancel()
        guard !reachable, isRemoteControlled else { return }
        unreachableTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: (self?.unreachableTimeoutSeconds ?? 30) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.isRemoteControlled else { return }
            self.end()
        }
    }

    func startWorkout(activityType: HKWorkoutActivityType, planDay: PlanDayDTO?) {
        self.planDay = planDay
        currentExerciseIndex = 0
        loggedSets = [:]
        didFinish = false
        heartRate = 0
        activeEnergyKcal = 0

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let start = Date()
            startDate = start
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }
            startTimer()
        } catch {
            print("FitTrack: Workout-Session konnte nicht gestartet werden: \(error)")
        }
    }

    /// Vom iPhone angefordertes Workout: startet dieselbe HKWorkoutSession wie
    /// ein lokal gestartetes Training, damit die Watch-Sensoren (u.a. Herzfrequenz)
    /// aktiv sind, sendet die Werte aber laufend zurück ans iPhone statt sie
    /// hier lokal satzweise zu erfassen.
    func startRemoteMonitoring(activityType: HKWorkoutActivityType, sessionId: String, activityName: String) {
        // Das iPhone kann denselben Start-Befehl mehrfach senden (z.B. wenn die
        // Watch erst kurz nach dem ersten Versuch erreichbar wurde). Läuft für
        // diese Session bereits eine Messung, nicht erneut eine HKWorkoutSession
        // starten - das würde die laufende Session unterbrechen/fehlschlagen.
        if isRemoteControlled, remoteSessionId == sessionId {
            return
        }
        if isRemoteControlled, remoteSessionId == nil, session != nil {
            // `handle(_:)` hat die Session bereits vorab gestartet (ausgelöst
            // durch `startWatchApp` vom iPhone) - nur die Metadaten ergänzen,
            // statt eine zweite, konkurrierende HKWorkoutSession zu starten.
            pendingRemoteSessionTimeoutTask?.cancel()
            remoteSessionId = sessionId
            remoteActivityName = activityName
            return
        }
        pendingRemoteSessionTimeoutTask?.cancel()
        remoteSessionId = sessionId
        isRemoteControlled = true
        remoteActivityName = activityName
        startWorkout(activityType: activityType, planDay: nil)
    }

    /// Wird von `WatchAppDelegate.handle(_:)` aufgerufen, sobald das iPhone die
    /// Watch-App gezielt über HealthKit für ein Training startet. Beginnt die
    /// HKWorkoutSession sofort (statt erst nach dem WatchConnectivity-Roundtrip),
    /// damit watchOS diese Session als die "erwartete" erkennt und die
    /// verlängerte Hintergrund-Laufzeit dafür gewährt - andernfalls dimmt der
    /// Bildschirm zu früh und die Verbindung zum iPhone bricht ab. Die
    /// eigentliche Session-ID/der Name kommen kurz danach per
    /// WatchConnectivity und werden dann in `startRemoteMonitoring` ergänzt.
    func beginPendingRemoteSession(activityType: HKWorkoutActivityType) {
        guard session == nil else { return }
        remoteSessionId = nil
        isRemoteControlled = true
        remoteActivityName = nil
        startWorkout(activityType: activityType, planDay: nil)

        // Sicherheitsnetz: kommt die Start-Bestätigung vom iPhone nie an (z.B.
        // weil das Training dort sofort wieder abgebrochen wurde, bevor die
        // Nachricht zugestellt war), würde diese vorab gestartete Session sonst
        // für immer laufen - die Watch-App bliebe dann dauerhaft "aktiv" und
        // offen, statt automatisch zum Zifferblatt zurückzukehren.
        pendingRemoteSessionTimeoutTask?.cancel()
        pendingRemoteSessionTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.isRemoteControlled, self.remoteSessionId == nil else { return }
            self.end()
        }
    }

    func logSet(reps: Int, weightKg: Double) {
        loggedSets[currentExerciseIndex, default: []].append(DraftSet(reps: reps, weightKg: weightKg))
        currentSetCount = loggedSets[currentExerciseIndex]?.count ?? 0
    }

    func nextExercise() {
        guard let planDay, currentExerciseIndex < planDay.items.count - 1 else { return }
        currentExerciseIndex += 1
        currentSetCount = loggedSets[currentExerciseIndex]?.count ?? 0
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func end() {
        pendingRemoteSessionTimeoutTask?.cancel()
        unreachableTimeoutTask?.cancel()
        averageHeartRateAtEnd = builder?.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let end = Date()
        session?.end()
        timer?.invalidate()

        guard let builder else {
            finishAndSend(healthKitWorkout: nil, endDate: end)
            return
        }

        Task {
            do {
                try await builder.endCollection(at: end)
                let workout = try await builder.finishWorkout()
                finishAndSend(healthKitWorkout: workout, endDate: end)
            } catch {
                print("FitTrack: Fehler beim Beenden der Workout-Session: \(error)")
                finishAndSend(healthKitWorkout: nil, endDate: end)
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
                if self.isRemoteControlled, self.elapsedSeconds > self.maxRemoteSessionDuration {
                    self.end()
                }
            }
        }
    }

    private func finishAndSend(healthKitWorkout: HKWorkout?, endDate: Date) {
        guard let startDate else { return }

        if isRemoteControlled {
            let result = RemoteWorkoutResultDTO(
                sessionId: remoteSessionId ?? "",
                startDate: startDate,
                endDate: endDate,
                totalEnergyBurnedKcal: activeEnergyKcal > 0 ? activeEnergyKcal : nil,
                averageHeartRate: averageHeartRateAtEnd,
                healthKitWorkoutUUID: healthKitWorkout?.uuid.uuidString
            )
            WatchConnectivityManager.shared.sendRemoteWorkoutResult(result)
            isRemoteControlled = false
            remoteSessionId = nil
            didFinish = true
            return
        }

        let exercises: [CompletedExerciseDTO] = (planDay?.items ?? []).enumerated().compactMap { index, item in
            guard let sets = loggedSets[index], !sets.isEmpty else { return nil }
            let setDTOs = sets.map { CompletedSetDTO(reps: $0.reps, weightKg: $0.weightKg, isWarmup: false) }
            return CompletedExerciseDTO(id: UUID().uuidString, exerciseId: item.exerciseId, exerciseName: item.exerciseName, sets: setDTOs)
        }

        let dto = CompletedWorkoutDTO(
            id: UUID().uuidString,
            startDate: startDate,
            endDate: endDate,
            activityName: planDay?.dayName ?? "Workout",
            totalEnergyBurnedKcal: activeEnergyKcal > 0 ? activeEnergyKcal : nil,
            averageHeartRate: averageHeartRateAtEnd,
            exercises: exercises,
            healthKitWorkoutUUID: healthKitWorkout?.uuid.uuidString
        )

        WatchConnectivityManager.shared.sendCompletedWorkout(dto)
        lastSummary = dto
        didFinish = true
    }

    private func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics else { return }
        if statistics.quantityType == HKQuantityType(.heartRate) {
            if let value = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                heartRate = value
                if isRemoteControlled, let sessionId = remoteSessionId {
                    WatchConnectivityManager.shared.sendHeartRateUpdate(HeartRateUpdateDTO(sessionId: sessionId, bpm: value))
                }
            }
        } else if statistics.quantityType == HKQuantityType(.activeEnergyBurned) {
            if let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                activeEnergyKcal = value
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.sessionState = toState
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("FitTrack: Workout-Session Fehler: \(error)")
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)
            Task { @MainActor in
                self.updateForStatistics(statistics)
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
