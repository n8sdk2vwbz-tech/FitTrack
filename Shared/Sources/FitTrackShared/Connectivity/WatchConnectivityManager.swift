import Foundation
import WatchConnectivity

/// Verbindet iPhone- und Watch-App über WatchConnectivity.
/// Der heutige Trainingsplan wird per `updateApplicationContext` an die Watch
/// übertragen (nur der letzte Stand zählt), abgeschlossene Workouts werden
/// per `transferUserInfo` zuverlässig zurück ans iPhone geschickt, auch wenn
/// die Watch beim Senden gerade nicht erreichbar ist. Für die Fernsteuerung
/// eines Watch-Workouts (Start/Stop/Live-Herzfrequenz) wird `sendMessage`
/// genutzt, das nur bei erreichbarer Gegenstelle sofort zugestellt wird.
public final class WatchConnectivityManager: NSObject, ObservableObject {

    public static let shared = WatchConnectivityManager()

    @Published public var receivedPlanDay: PlanDayDTO?
    @Published public var receivedCompletedWorkout: CompletedWorkoutDTO?
    @Published public var isCounterpartReachable: Bool = false

    /// Anfrage, ein Watch-Workout fernzusteuern (fürs Erfassen der Herzfrequenz
    /// eines auf dem iPhone gestarteten Trainings).
    @Published public var remoteStartRequest: RemoteWorkoutStartDTO?
    @Published public var remoteStopRequest: RemoteWorkoutStopDTO?
    @Published public var heartRateUpdate: HeartRateUpdateDTO?
    @Published public var remoteWorkoutResult: RemoteWorkoutResultDTO?
    @Published public var restTimerTrigger: RestTimerTriggerDTO?
    @Published public var restTimerStatus: RestTimerStatusDTO?
    @Published public var remoteSetCompleted: RemoteSetCompletedDTO?
    /// Ob der HF-basierte Satzpausen-Timer aktiv sein soll - lebt als
    /// Einstellung auf dem iPhone (die Watch hat keine eigene Settings-UI)
    /// und wird per `updateApplicationContext` synchronisiert, damit auch ein
    /// direkt auf der Watch gestartetes (nicht ferngesteuertes) Training
    /// davon weiß, siehe `sendRestTimerPreference`.
    @Published public var restTimerEnabled: Bool = false

    private let planContextKey = "planDay"
    private let restTimerEnabledContextKey = "restTimerEnabled"
    private let workoutInfoKey = "completedWorkout"
    /// `updateApplicationContext` ersetzt bei jedem Aufruf das gesamte
    /// Kontext-Dictionary - ohne diesen Zwischenspeicher würde ein Aufruf von
    /// `sendRestTimerPreference` den zuletzt gesendeten Plan (oder umgekehrt)
    /// überschreiben, statt beide Werte nebeneinander zu halten.
    private var lastPlanData: Data?

    private enum MessageType: String {
        case remoteStart, remoteStop, heartRate, remoteResult, restTimerTrigger, restTimerStatus, remoteSetCompleted
    }

    private override init() {
        super.init()
    }

    public func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// iPhone -> Watch: heutigen Plan übertragen.
    public func sendPlanDay(_ day: PlanDayDTO) {
        guard let data = try? JSONEncoder().encode(day) else { return }
        lastPlanData = data
        resendContext()
    }

    /// iPhone -> Watch: aktuellen Stand der Satzpausen-Timer-Einstellung
    /// übertragen - beim App-Start und immer, wenn sie in den Einstellungen
    /// geändert wird.
    public func sendRestTimerPreference(_ enabled: Bool) {
        restTimerEnabled = enabled
        resendContext()
    }

    private func resendContext() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var context: [String: Any] = [restTimerEnabledContextKey: restTimerEnabled]
        if let lastPlanData { context[planContextKey] = lastPlanData }
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Watch -> iPhone: abgeschlossenes Workout übertragen.
    public func sendCompletedWorkout(_ workout: CompletedWorkoutDTO) {
        guard WCSession.isSupported() else { return }
        guard let data = try? JSONEncoder().encode(workout) else { return }
        WCSession.default.transferUserInfo([workoutInfoKey: data])
    }

    /// iPhone -> Watch: Watch soll für dieses Training die Herzfrequenz messen.
    public func sendRemoteWorkoutStart(_ dto: RemoteWorkoutStartDTO) {
        send(type: .remoteStart, payload: dto)
    }

    /// iPhone -> Watch: das ferngesteuerte Watch-Workout beenden.
    public func sendRemoteWorkoutStop(_ dto: RemoteWorkoutStopDTO) {
        let reachable = WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
        print("🔧 RestTimerDebug: sendRemoteWorkoutStop sessionId=\(dto.sessionId), discard=\(dto.discard), reachable=\(reachable)")
        send(type: .remoteStop, payload: dto)
        // Zusätzlich garantiert zustellen (nicht nur bei sofortiger
        // Erreichbarkeit über sendMessage): geht der Stop-Befehl verloren
        // (z.B. eine kurze Verbindungslücke genau in dem Moment), würde die
        // Watch sonst für immer glauben, das Training laufe noch - die
        // App bliebe dauerhaft aktiv und offen, statt zum Zifferblatt
        // zurückzukehren. transferUserInfo liefert auch verspätet zu, sobald
        // die Verbindung wieder da ist; ein verspäteter Stop ist immer sicher.
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(dto) else { return }
        WCSession.default.transferUserInfo(["type": MessageType.remoteStop.rawValue, "payload": data])
    }

    /// Watch -> iPhone: laufende Live-Herzfrequenz während eines ferngesteuerten Trainings.
    public func sendHeartRateUpdate(_ dto: HeartRateUpdateDTO) {
        send(type: .heartRate, payload: dto)
    }

    /// Watch -> iPhone: Abschlussdaten (Kalorien, Ø-Herzfrequenz, HealthKit-UUID) nach dem Beenden.
    public func sendRemoteWorkoutResult(_ dto: RemoteWorkoutResultDTO) {
        send(type: .remoteResult, payload: dto)
        // Genau wie beim Stop-Befehl zusätzlich garantiert zustellen: ist das
        // iPhone im Moment des Beendens gerade kurz nicht erreichbar (z.B.
        // Bildschirm der Watch war kurz zuvor dunkel), ginge das Ergebnis
        // sonst komplett verloren statt nur verspätet anzukommen - die
        // Watch berechnet diese Werte nur einmal, es gibt keinen erneuten Versuch.
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(dto) else { return }
        WCSession.default.transferUserInfo(["type": MessageType.remoteResult.rawValue, "payload": data])
    }

    /// iPhone -> Watch: ein Satz wurde in einem ferngesteuerten Training
    /// gerade abgehakt, siehe `RestTimerTriggerDTO`. Bewusst nur per
    /// `sendMessage` (kein garantierter Re-Versand): verpasst die Watch einen
    /// einzelnen Trigger durch eine kurze Verbindungslücke, ist das nur eine
    /// verpasste Erinnerung für diesen einen Satz, kein Datenverlust.
    public func sendRestTimerTrigger(_ dto: RestTimerTriggerDTO) {
        let reachable = WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
        print("🔧 RestTimerDebug: sendRestTimerTrigger sessionId=\(dto.sessionId), reachable=\(reachable)")
        send(type: .restTimerTrigger, payload: dto)
    }

    /// Watch -> iPhone: Stand der Satzpausen-Überwachung, damit `ActiveWorkoutView`
    /// dieselbe Anzeige zeigen und bei Abschluss eine Mitteilung auslösen kann.
    public func sendRestTimerStatus(_ dto: RestTimerStatusDTO) {
        send(type: .restTimerStatus, payload: dto)
    }

    /// Watch -> iPhone: ein Satz wurde direkt auf der Watch abgehakt (siehe
    /// `RemoteSetCompletedDTO`). Genau wie beim Stop-/Ergebnis-Befehl
    /// zusätzlich garantiert zustellen - anders als beim reinen Pausen-Timer
    /// (verpasste Erinnerung wäre unschön, aber egal) würde ein verlorener
    /// Satz hier sonst wirklich fehlen: die gespeicherte Einheit hätte am
    /// Ende einen Satz weniger, als tatsächlich trainiert wurde.
    public func sendRemoteSetCompleted(_ dto: RemoteSetCompletedDTO) {
        send(type: .remoteSetCompleted, payload: dto)
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(dto) else { return }
        WCSession.default.transferUserInfo(["type": MessageType.remoteSetCompleted.rawValue, "payload": data])
    }

    private func send<T: Encodable>(type: MessageType, payload: T) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(payload) else { return }
        WCSession.default.sendMessage(["type": type.rawValue, "payload": data], replyHandler: nil, errorHandler: nil)
    }

    private func handleIncoming(_ userInfo: [String: Any]) {
        if let data = userInfo[planContextKey] as? Data,
           let day = try? JSONDecoder().decode(PlanDayDTO.self, from: data) {
            DispatchQueue.main.async { self.receivedPlanDay = day }
        }
        if let enabled = userInfo[restTimerEnabledContextKey] as? Bool {
            DispatchQueue.main.async { self.restTimerEnabled = enabled }
        }
        if let data = userInfo[workoutInfoKey] as? Data,
           let workout = try? JSONDecoder().decode(CompletedWorkoutDTO.self, from: data) {
            DispatchQueue.main.async { self.receivedCompletedWorkout = workout }
        }
        // Für per transferUserInfo garantiert zugestellte Nachrichten (aktuell
        // nur der Stop-Befehl) dasselbe type/payload-Format wie sendMessage
        // verstehen - no-op, falls diese Keys hier nicht vorkommen.
        handleIncomingMessage(userInfo)
    }

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let typeRaw = message["type"] as? String,
              let type = MessageType(rawValue: typeRaw),
              let data = message["payload"] as? Data else { return }

        switch type {
        case .remoteStart:
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutStartDTO.self, from: data) else {
                print("🔧 RestTimerDebug: .remoteStart Nachricht konnte nicht dekodiert werden")
                return
            }
            print("🔧 RestTimerDebug: .remoteStart empfangen, sessionId=\(dto.sessionId), restTimerEnabled=\(dto.restTimerEnabled)")
            DispatchQueue.main.async {
                self.remoteStartRequest = dto
                // Zuverlässiger als der reine Kontext-Sync (siehe
                // `RemoteWorkoutStartDTO.restTimerEnabled`) - überschreibt den
                // synchronisierten Stand mit dem aktuellen zum Trainingsstart.
                self.restTimerEnabled = dto.restTimerEnabled
            }
        case .remoteStop:
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutStopDTO.self, from: data) else {
                print("🔧 RestTimerDebug: .remoteStop Nachricht konnte nicht dekodiert werden")
                return
            }
            print("🔧 RestTimerDebug: .remoteStop empfangen, sessionId=\(dto.sessionId), discard=\(dto.discard)")
            DispatchQueue.main.async { self.remoteStopRequest = dto }
        case .heartRate:
            guard let dto = try? JSONDecoder().decode(HeartRateUpdateDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.heartRateUpdate = dto }
        case .remoteResult:
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutResultDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.remoteWorkoutResult = dto }
        case .restTimerTrigger:
            guard let dto = try? JSONDecoder().decode(RestTimerTriggerDTO.self, from: data) else {
                print("🔧 RestTimerDebug: .restTimerTrigger Nachricht konnte nicht dekodiert werden")
                return
            }
            print("🔧 RestTimerDebug: .restTimerTrigger empfangen, sessionId=\(dto.sessionId)")
            DispatchQueue.main.async { self.restTimerTrigger = dto }
        case .restTimerStatus:
            guard let dto = try? JSONDecoder().decode(RestTimerStatusDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.restTimerStatus = dto }
        case .remoteSetCompleted:
            guard let dto = try? JSONDecoder().decode(RemoteSetCompletedDTO.self, from: data) else { return }
            print("🔧 RestTimerDebug: .remoteSetCompleted empfangen, sessionId=\(dto.sessionId)")
            DispatchQueue.main.async { self.remoteSetCompleted = dto }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        DispatchQueue.main.async { self.isCounterpartReachable = session.isReachable }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isCounterpartReachable = session.isReachable }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncoming(applicationContext)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
