import Foundation
import HealthKit
import Combine
import WatchKit
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
    /// Ob gerade auf die Erholung nach einem Satz gewartet wird (siehe
    /// `startRestMonitoringIfNeeded`) - treibt die Anzeige in
    /// `LiveWorkoutView`/`RemoteMonitoringView`.
    @Published var isRestTimerActive: Bool = false
    @Published var restElapsedSeconds: TimeInterval = 0

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
    private var restTimerTriggerCancellable: AnyCancellable?
    private var restTimerTask: Task<Void, Never>?
    /// Siehe `end(discard:)`/`waitForStoppedWithTimeout` - wird bedient, sobald
    /// `HKWorkoutSessionDelegate` den Übergang zu `.stopped` meldet (oder nach
    /// Ablauf des Sicherheits-Timeouts, falls dieser Übergang aus irgendeinem
    /// Grund ausbleibt).
    private var stoppedContinuation: CheckedContinuation<Void, Never>?
    /// Einmal pro Training abgefragt (siehe `startWorkout`) statt bei jeder
    /// Satzpause neu, da sich HFmax/Ruhepuls innerhalb einer Einheit nicht ändern.
    /// Dient nur noch als Rückfall-Obergrenze (siehe `restTargetHeartRate`),
    /// solange für den gerade beendeten Satz noch keine eigene Spitzen-HF
    /// vorliegt (z.B. beim allerersten Satz eines Trainings).
    private var cachedMaxHeartRate: Double?
    private var cachedRestingHeartRate: Double?
    /// Höchste seit dem Ende der letzten Pause gemessene Herzfrequenz - bildet
    /// die Obergrenze der HFR-Berechnung für die kommende Pause (siehe
    /// `restTargetHeartRate`). Ein pauschaler alters-geschätzter HFmax-Wert
    /// setzt die Obergrenze unabhängig davon, wie anstrengend der tatsächlich
    /// gerade absolvierte Satz war - ein leichter Aufwärmsatz und ein
    /// maximaler Arbeitssatz hätten so denselben Erholungs-Zielwert, obwohl
    /// nur Letzterer die Herzfrequenz wirklich in Richtung HFmax treibt.
    private var currentSetPeakHeartRate: Double = 0
    /// Schnappschuss von `currentSetPeakHeartRate` beim Start der aktuell
    /// laufenden Pause - `currentSetPeakHeartRate` wird sofort danach
    /// zurückgesetzt, um schon während der Pause die Spitze des nächsten
    /// Satzes zu erfassen, der Zielwert dieser Pause soll sich aber nicht
    /// nachträglich mitverändern.
    private var restPeakHeartRateSnapshot: Double?

    /// Wie lange das iPhone nicht erreichbar sein darf, bevor eine
    /// ferngesteuerte Session selbst beendet wird (siehe `handleReachabilityChange`).
    /// `isReachable` wird schon durch einen dunklen Watch-Bildschirm oder eine
    /// kurze Bluetooth-Lücke kurzzeitig false - beides während eines normalen
    /// Trainings völlig normal und meist nach wenigen Sekunden wieder vorbei.
    /// War dieser Wert bei 30s, beendete (und speicherte!) dieses
    /// Sicherheitsnetz regelmäßig noch laufende Trainings von selbst, obwohl
    /// gar nichts wirklich schiefgelaufen war. 5 Minuten behoben das, hatten
    /// aber einen echten Zielkonflikt: kommt der eigentliche Abbrechen-/
    /// Beenden-Befehl aus irgendeinem Grund (z.B. eine hartnäckigere
    /// Verbindungsstörung) tatsächlich gar nicht an, hängt die Watch-App bis
    /// zu 5 Minuten fest, statt sich zeitnah selbst aufzulösen - spürbar
    /// länger, als es sich richtig anfühlt. 90 Sekunden sind immer noch weit
    /// über allem, was ein normaler kurzer Aussetzer braucht, lassen die App
    /// im Fehlerfall aber deutlich früher wieder los.
    private let unreachableTimeoutSeconds: UInt64 = 90
    /// Absolute Obergrenze für eine ferngesteuerte Session, unabhängig von der
    /// Erreichbarkeit - deckt den Fall ab, dass das iPhone zwar verbunden
    /// bleibt (z.B. App im Hintergrund weiterhin aktiv), aber nie explizit
    /// "Beenden" gesendet hat. Ohne dieses zweite, unabhängige Sicherheitsnetz
    /// könnte eine Session sonst unbegrenzt "aktiv" bleiben, obwohl real
    /// längst kein Training mehr stattfindet. War zuvor bei 60 Minuten - das
    /// hat reguläre, längere Krafttrainings-Einheiten vorzeitig beendet und
    /// dabei die Herzfrequenz-Aufzeichnung mitten im Training gestoppt.
    private let maxRemoteSessionDuration: TimeInterval = 3 * 60 * 60

    /// Anteil der Herzfrequenzreserve (Karvonen: Ruhepuls + Anteil ×
    /// (HFmax − Ruhepuls)), ab dessen Erreichen der nächste Satz als sinnvoll
    /// startbar gilt - Richtwert 50-60% aus der Literatur zu HF-basierten
    /// Satzpausen, hier die Mitte davon.
    private let restTargetHRRFraction: Double = 0.55
    /// Mindestwartezeit, bevor überhaupt auf die Herzfrequenz geschaut wird -
    /// ohne das könnte z.B. nach einem sehr leichten Satz sofort "bereit"
    /// gemeldet werden, obwohl gerade erst aufgehört wurde.
    private let restMinWaitSeconds: TimeInterval = 20
    /// Obergrenze, falls die Herzfrequenz aus irgendeinem Grund (z.B.
    /// Sensor-Aussetzer) nicht rechtzeitig auf den Zielwert fällt - lieber
    /// nach dieser Zeit trotzdem erinnern, als den Nutzer unbegrenzt warten
    /// zu lassen.
    private let restMaxWaitSeconds: TimeInterval = 240
    /// Rückfall-Wartezeit, falls HFmax/Ruhepuls gar nicht ermittelbar sind
    /// (z.B. kein Geburtsdatum in Health hinterlegt) - angelehnt an die
    /// klassische Hypertrophie-Satzpausen-Empfehlung (30-90s).
    private let restFallbackSeconds: TimeInterval = 90
    /// Schwelle (Anteil der Herzfrequenzreserve), unter der ein Satz als kaum
    /// anstrengend gilt (siehe `isLowIntensitySet`) - z.B. ein Aufwärmsatz mit
    /// wenig Gewicht. Realer beobachteter Fall: Ruhepuls 57.5, Satz-Spitze nur
    /// 81 (≈18% HFR) ergab einen Zielwert von 70.4 - niedriger, als die HF
    /// kurz danach durch normale Schwankung ohnehin lag (82-92), die Pause
    /// wäre so bis zu 4 Minuten für einen fast anstrengungslosen Satz gelaufen.
    private let restLowIntensityHRRFraction: Double = 0.20

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
        // Beim ferngesteuerten Training (vom iPhone gestartet) loggt die
        // Watch selbst keine Sätze - ohne dieses Signal vom iPhone wüsste sie
        // nie, wann ein Satz abgeschlossen wurde, um die Satzpausen-
        // Überwachung zu starten (siehe `startRestMonitoringIfNeeded`).
        restTimerTriggerCancellable = WatchConnectivityManager.shared.$restTimerTrigger
            .compactMap { $0 }
            .sink { [weak self] dto in
                Task { @MainActor in
                    print("🔧 RestTimerDebug: Trigger-Sink ausgelöst, dto.sessionId=\(dto.sessionId), remoteSessionId=\(self?.remoteSessionId ?? "nil")")
                    guard self?.remoteSessionId == dto.sessionId else {
                        print("🔧 RestTimerDebug: Trigger verworfen - sessionId stimmt nicht überein")
                        return
                    }
                    self?.startRestMonitoringIfNeeded()
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
        currentSetPeakHeartRate = 0
        restPeakHeartRateSnapshot = nil

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
            cacheHeartRateBaselineIfNeeded()
        } catch {
            print("FitTrack: Workout-Session konnte nicht gestartet werden: \(error)")
        }
    }

    /// Einmal pro Training abgefragt statt bei jeder Satzpause neu (siehe
    /// `cachedMaxHeartRate`/`cachedRestingHeartRate`). Läuft im Hintergrund -
    /// das Training soll nicht auf diese (u.U. mehrere Sekunden dauernde)
    /// HealthKit-Abfrage warten müssen, um zu starten.
    private func cacheHeartRateBaselineIfNeeded() {
        Task { [weak self] in
            let maxHR = HealthKitManager.shared.fetchEstimatedMaxHeartRate()
            let restingHR = await HealthKitManager.shared.fetchLatestRestingHeartRate()
            await MainActor.run {
                self?.cachedMaxHeartRate = maxHR
                self?.cachedRestingHeartRate = restingHR
            }
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

    /// Direkt auf der Watch ausgelöstes Satz-Abhaken (siehe `RemoteMonitoringView`)
    /// - erspart bei einem ferngesteuerten Training das Umschalten aufs iPhone.
    /// Die Watch kennt hier keine Übungen/Sätze (siehe `startRemoteMonitoring`,
    /// `planDay: nil`), meldet dem iPhone deshalb nur "irgendein Satz fertig"
    /// - das iPhone markiert dort selbst den nächsten offenen Satz (siehe
    /// `ActiveWorkoutView.completeNextSetFromWatch`). Startet die HF-Überwachung
    /// direkt selbst, statt auf den Rückweg über `restTimerTrigger` zu warten -
    /// die Watch misst die Herzfrequenz ohnehin selbst.
    func completeSetRemotely() {
        guard isRemoteControlled, let remoteSessionId else { return }
        WatchConnectivityManager.shared.sendRemoteSetCompleted(RemoteSetCompletedDTO(sessionId: remoteSessionId))
        startRestMonitoringIfNeeded()
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
            // Anders als beim Reachability- oder 3-Stunden-Sicherheitsnetz:
            // hier kam nie eine bestätigte Session-ID vom iPhone an, es gibt
            // also garantiert kein echtes, laufendes Training zu bewahren -
            // verwerfen statt (fälschlich) als Sekunden-kurzes "Workout" in
            // Health zu speichern.
            self.end(discard: true)
        }
    }

    func logSet(reps: Int, weightKg: Double) {
        loggedSets[currentExerciseIndex, default: []].append(DraftSet(reps: reps, weightKg: weightKg))
        currentSetCount = loggedSets[currentExerciseIndex]?.count ?? 0
        startRestMonitoringIfNeeded()
    }

    /// Startet die HF-basierte Satzpausen-Überwachung: sobald die
    /// Herzfrequenz auf einen Erholungs-Zielwert fällt (Karvonen-Formel,
    /// 50-60% der Herzfrequenzreserve laut Literatur zu satzweiser Erholung),
    /// vibriert die Watch. Als Obergrenze der Reserve dient bevorzugt die im
    /// gerade beendeten Satz tatsächlich erreichte Spitzen-HF (siehe
    /// `currentSetPeakHeartRate`) statt eines pauschalen alters-geschätzten
    /// HFmax - ein leichter Satz soll keinen ebenso hohen Erholungs-Zielwert
    /// verlangen wie ein wirklich maximaler. Ohne verlässliche Ruhepuls-Basis
    /// (z.B. kein Geburtsdatum in Health) wird stattdessen nach
    /// `restFallbackSeconds` erinnert. Läuft für lokal geloggte (siehe
    /// `logSet`) UND ferngesteuerte (siehe `restTimerTriggerCancellable`)
    /// Trainings gleich ab.
    func startRestMonitoringIfNeeded() {
        guard WatchConnectivityManager.shared.restTimerEnabled else {
            print("🔧 RestTimerDebug: startRestMonitoringIfNeeded abgebrochen - restTimerEnabled=false")
            return
        }
        // Schnappschuss VOR dem Zurücksetzen sichern (siehe
        // `restPeakHeartRateSnapshot`-Kommentar) - ab jetzt sammelt
        // `currentSetPeakHeartRate` bereits die Spitze des nächsten Satzes.
        restPeakHeartRateSnapshot = currentSetPeakHeartRate > 0 ? currentSetPeakHeartRate : nil
        currentSetPeakHeartRate = 0
        print("🔧 RestTimerDebug: startRestMonitoringIfNeeded startet Überwachung (maxHR=\(cachedMaxHeartRate?.description ?? "nil"), restingHR=\(cachedRestingHeartRate?.description ?? "nil"), setPeakHR=\(restPeakHeartRateSnapshot?.description ?? "nil"), targetHR=\(restTargetHeartRate?.description ?? "nil"))")
        restTimerTask?.cancel()
        isRestTimerActive = true
        restElapsedSeconds = 0
        let startedAt = Date()
        sendRestTimerStatusIfRemote()

        restTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.restElapsedSeconds = Date().timeIntervalSince(startedAt)
                print("🔧 RestTimerDebug: Tick t=\(Int(self.restElapsedSeconds))s heartRate=\(self.heartRate) targetHR=\(self.restTargetHeartRate?.description ?? "nil") lowIntensity=\(self.isLowIntensitySet)")
                if self.isReadyForNextSet() {
                    self.completeRestMonitoring()
                    return
                }
                self.sendRestTimerStatusIfRemote()
            }
        }
    }

    /// Nur bei ferngesteuerten Trainings relevant - `ActiveWorkoutView` auf
    /// dem iPhone kennt die Herzfrequenz sonst gar nicht selbst.
    private func sendRestTimerStatusIfRemote() {
        guard isRemoteControlled, let remoteSessionId else { return }
        WatchConnectivityManager.shared.sendRestTimerStatus(
            RestTimerStatusDTO(sessionId: remoteSessionId, isActive: isRestTimerActive, elapsedSeconds: restElapsedSeconds)
        )
    }

    private var restTargetHeartRate: Double? {
        guard let restingHR = cachedRestingHeartRate else { return nil }
        // Bevorzugt die tatsächliche Spitzen-HF des gerade beendeten Satzes
        // als Obergrenze - nur falls die (noch) nicht vorliegt (z.B. beim
        // allerersten Satz, bevor der erste HF-Sample eintraf), Rückfall auf
        // den pauschalen alters-geschätzten Wert.
        if let peak = restPeakHeartRateSnapshot, peak > restingHR {
            return restingHR + restTargetHRRFraction * (peak - restingHR)
        }
        guard let maxHR = cachedMaxHeartRate, maxHR > restingHR else { return nil }
        return restingHR + restTargetHRRFraction * (maxHR - restingHR)
    }

    /// Siehe `restLowIntensityHRRFraction`-Kommentar: stieg die HF während des
    /// Satzes kaum über den Ruhepuls, war der Satz kaum anstrengend genug, um
    /// einen aussagekräftigen HF-Zielwert daraus abzuleiten - die Erholung
    /// gilt dann bereits nach der Mindestwartezeit als ausreichend.
    private var isLowIntensitySet: Bool {
        guard let peak = restPeakHeartRateSnapshot,
              let restingHR = cachedRestingHeartRate,
              let maxHR = cachedMaxHeartRate,
              maxHR > restingHR else { return false }
        return (peak - restingHR) / (maxHR - restingHR) < restLowIntensityHRRFraction
    }

    private func isReadyForNextSet() -> Bool {
        guard restElapsedSeconds >= restMinWaitSeconds else { return false }
        if isLowIntensitySet { return true }
        guard let target = restTargetHeartRate else {
            return restElapsedSeconds >= restFallbackSeconds
        }
        if heartRate > 0, heartRate <= target { return true }
        return restElapsedSeconds >= restMaxWaitSeconds
    }

    private func completeRestMonitoring() {
        isRestTimerActive = false
        restTimerTask = nil
        WKInterfaceDevice.current().play(.notification)
        sendRestTimerStatusIfRemote()
    }

    func nextExercise() {
        guard let planDay, currentExerciseIndex < planDay.items.count - 1 else { return }
        currentExerciseIndex += 1
        currentSetCount = loggedSets[currentExerciseIndex]?.count ?? 0
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Wartet auf den `HKWorkoutSessionDelegate`-Übergang zu `.stopped` (siehe
    /// `stoppedContinuation`), höchstens aber `timeoutSeconds` - bleibt dieser
    /// Übergang aus irgendeinem Grund aus, lieber trotzdem weitermachen als
    /// für immer zu hängen (siehe `end(discard:)`-Kommentar zur Reihenfolge).
    private func waitForStoppedWithTimeout(timeoutSeconds: UInt64 = 5) async {
        guard let session, session.state != .stopped, session.state != .ended else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.stoppedContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                guard let self, let pending = self.stoppedContinuation else { return }
                self.stoppedContinuation = nil
                print("🔧 RestTimerDebug: waitForStoppedWithTimeout - Timeout, .stopped nie gemeldet")
                pending.resume()
            }
        }
    }

    /// - Parameter discard: true bei einem Abbruch (statt regulärem Beenden) -
    ///   verwirft die HKWorkoutSession dann per `discardWorkout()`, statt sie
    ///   als echtes HealthKit-Workout zu speichern. Ohne diese Unterscheidung
    ///   landete auch bei einem sofort abgebrochenen Training ein (sehr
    ///   kurzes) Workout in Health, das dann automatisch als eigene Einheit
    ///   importiert wurde, obwohl real gar nicht trainiert wurde.
    ///
    ///   Der Verwerfen-Fall ruft `discardWorkout()` bewusst SOFORT auf, ohne
    ///   auf `.stopped` zu warten: ein Test zeigte, dass die Einheit trotz
    ///   `discardWorkout()` in Health landete, sobald die Session zuvor schon
    ///   `.stopped` erreicht hatte - anscheinend beginnt das System ab diesem
    ///   Zustand bereits mit einer eigenen Finalisierung/Sicherung der Daten,
    ///   die `discardWorkout()` danach nicht mehr vollständig zurücknehmen
    ///   kann. Der reguläre Abschluss (kein Verwerfen) wartet weiterhin auf
    ///   `.stopped`, bevor `endCollection`/`finishWorkout` aufgerufen werden -
    ///   das ist die von Apple dokumentierte Reihenfolge für ein VOLLSTÄNDIGES
    ///   Workout und hier unproblematisch, da hier ohnehin gespeichert werden soll.
    func end(discard: Bool = false) {
        print("🔧 RestTimerDebug: end(discard: \(discard)) aufgerufen, sessionState=\(sessionState.rawValue)")
        pendingRemoteSessionTimeoutTask?.cancel()
        unreachableTimeoutTask?.cancel()
        restTimerTask?.cancel()
        isRestTimerActive = false
        timer?.invalidate()
        let endDate = Date()

        guard let session, let builder else {
            print("🔧 RestTimerDebug: end() keine Session/Builder - finishAndSend direkt")
            finishAndSend(healthKitWorkout: nil, endDate: endDate, discarded: discard)
            return
        }

        if discard {
            print("🔧 RestTimerDebug: end() (discard) ruft stopActivity(), discardWorkout(), end() sofort/nacheinander auf")
            session.stopActivity(with: endDate)
            builder.discardWorkout()
            session.end()
            finishAndSend(healthKitWorkout: nil, endDate: endDate, discarded: true)
            return
        }

        print("🔧 RestTimerDebug: end() ruft session.stopActivity() auf")
        session.stopActivity(with: endDate)

        Task { @MainActor in
            await waitForStoppedWithTimeout()
            print("🔧 RestTimerDebug: end() .stopped erreicht (oder Timeout), sessionState=\(sessionState.rawValue)")
            averageHeartRateAtEnd = builder.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            do {
                try await builder.endCollection(at: endDate)
                let workout = try await builder.finishWorkout()
                // Die zuvor live mitgeschriebenen Werte (`activeEnergyKcal`,
                // `averageHeartRateAtEnd`) können knapp vor Trainingsende noch
                // unvollständig sein, wenn HealthKit die letzten Samples erst
                // nach diesem Zeitpunkt zustellt - das führte dazu, dass HF
                // oder Kalorien in ReadyLift/Strava fehlten, obwohl Apple
                // Fitness (das die fertige HKWorkout-Statistik erst NACH dem
                // Abschluss anzeigt) den korrekten Wert hatte. Deshalb hier
                // aus der fertigen, endgültigen HKWorkout-Statistik lesen.
                if let workout {
                    if let finalEnergy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        activeEnergyKcal = finalEnergy
                    }
                    if let finalHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) {
                        averageHeartRateAtEnd = finalHeartRate
                    }
                }
                print("🔧 RestTimerDebug: end() ruft session.end() auf")
                session.end()
                finishAndSend(healthKitWorkout: workout, endDate: endDate, discarded: false)
            } catch {
                print("FitTrack: Fehler beim Beenden der Workout-Session: \(error)")
                session.end()
                finishAndSend(healthKitWorkout: nil, endDate: endDate, discarded: false)
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

    private func finishAndSend(healthKitWorkout: HKWorkout?, endDate: Date, discarded: Bool) {
        print("🔧 RestTimerDebug: finishAndSend aufgerufen, startDate=\(startDate?.description ?? "nil"), isRemoteControlled=\(isRemoteControlled), discarded=\(discarded)")
        guard let startDate else {
            print("🔧 RestTimerDebug: finishAndSend abgebrochen - startDate nil, didFinish bleibt unverändert!")
            return
        }

        if isRemoteControlled {
            let finishedSessionId = remoteSessionId ?? ""
            isRemoteControlled = false
            remoteSessionId = nil
            didFinish = true
            print("🔧 RestTimerDebug: finishAndSend (remote) didFinish=true gesetzt")
            // Bei einem Abbruch wurde nichts gespeichert - es gibt nichts
            // Sinnvolles zu melden, und das iPhone hat seine Ansicht beim
            // Abbrechen ohnehin schon sofort geschlossen, ohne auf eine
            // Antwort zu warten.
            guard !discarded else { return }
            let result = RemoteWorkoutResultDTO(
                sessionId: finishedSessionId,
                startDate: startDate,
                endDate: endDate,
                totalEnergyBurnedKcal: activeEnergyKcal > 0 ? activeEnergyKcal : nil,
                averageHeartRate: averageHeartRateAtEnd,
                healthKitWorkoutUUID: healthKitWorkout?.uuid.uuidString
            )
            WatchConnectivityManager.shared.sendRemoteWorkoutResult(result)
            return
        }

        guard !discarded else {
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
                currentSetPeakHeartRate = max(currentSetPeakHeartRate, value)
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
        print("🔧 RestTimerDebug: HKWorkoutSessionDelegate didChangeTo \(toState.rawValue) from \(fromState.rawValue)")
        Task { @MainActor in
            self.sessionState = toState
            if toState == .stopped, let continuation = self.stoppedContinuation {
                self.stoppedContinuation = nil
                continuation.resume()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("🔧 RestTimerDebug: HKWorkoutSessionDelegate didFailWithError \(error)")
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
