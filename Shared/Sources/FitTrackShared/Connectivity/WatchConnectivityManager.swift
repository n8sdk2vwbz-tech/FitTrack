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

    private let planContextKey = "planDay"
    private let workoutInfoKey = "completedWorkout"

    private enum MessageType: String {
        case remoteStart, remoteStop, heartRate, remoteResult
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
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(day) else { return }
        try? WCSession.default.updateApplicationContext([planContextKey: data])
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
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutStartDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.remoteStartRequest = dto }
        case .remoteStop:
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutStopDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.remoteStopRequest = dto }
        case .heartRate:
            guard let dto = try? JSONDecoder().decode(HeartRateUpdateDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.heartRateUpdate = dto }
        case .remoteResult:
            guard let dto = try? JSONDecoder().decode(RemoteWorkoutResultDTO.self, from: data) else { return }
            DispatchQueue.main.async { self.remoteWorkoutResult = dto }
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
