import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// Live Activity fürs aktive Training (Sperrbildschirm/Dynamic Island) - siehe
/// `LiveActivityManager` (FitTrack-App-Target, startet/aktualisiert/beendet
/// sie) und `FitTrackWidgets/RestTimerLiveActivityWidget.swift` (Darstellung).
/// Nur auf iOS relevant, ActivityKit existiert nicht auf watchOS - der Rest
/// des `FitTrackShared`-Pakets wird aber auch für den Watch-Build kompiliert,
/// daher die `canImport`-Guard um die gesamte Datei.
@available(iOS 16.1, *)
public struct RestTimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var heartRate: Double
        public var isResting: Bool
        public var restElapsedSeconds: Int
        /// Angestrebte Herzfrequenz, ab der die Pause als beendet gilt - v.a.
        /// zum Testen/Kalibrieren der Formel mit angezeigt.
        public var restTargetHeartRate: Int?
        /// Name der Übung des nächsten noch offenen Satzes - "Fertig", wenn
        /// keiner mehr offen ist (alle Sätze abgehakt).
        public var nextExerciseName: String
        public var nextSetReps: Int
        public var nextSetWeightKg: Double?
        public var nextSetIsWarmup: Bool
        public var hasNextSet: Bool

        public init(heartRate: Double, isResting: Bool, restElapsedSeconds: Int, restTargetHeartRate: Int? = nil, nextExerciseName: String, nextSetReps: Int, nextSetWeightKg: Double?, nextSetIsWarmup: Bool, hasNextSet: Bool) {
            self.heartRate = heartRate
            self.isResting = isResting
            self.restElapsedSeconds = restElapsedSeconds
            self.restTargetHeartRate = restTargetHeartRate
            self.nextExerciseName = nextExerciseName
            self.nextSetReps = nextSetReps
            self.nextSetWeightKg = nextSetWeightKg
            self.nextSetIsWarmup = nextSetIsWarmup
            self.hasNextSet = hasNextSet
        }
    }

    public var sessionId: String

    public init(sessionId: String) {
        self.sessionId = sessionId
    }
}
#endif
