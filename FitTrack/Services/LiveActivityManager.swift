import Foundation
import ActivityKit
import FitTrackShared

/// Startet/aktualisiert/beendet die Live Activity fürs aktive Training (siehe
/// `RestTimerActivityAttributes`) - zeigt Pause-Zeit, aktuelle Herzfrequenz und
/// den nächsten Satz auf Sperrbildschirm/Dynamic Island, inkl. interaktivem
/// Abhaken/Wdh.-Anpassen direkt von dort (siehe `CompleteSetLiveActivityIntent`/
/// `AdjustNextSetRepsIntent`, die über `LiveActivityActionRelay` zurück in
/// diese App wirken, ohne dass `ActiveWorkoutView` die Widget-Extension direkt
/// kennen muss).
@available(iOS 16.1, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<RestTimerActivityAttributes>?

    private init() {}

    func start(sessionId: String, state: RestTimerActivityAttributes.ContentState) {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RestTimerActivityAttributes(sessionId: sessionId)
        let content = ActivityContent(state: state, staleDate: nil)
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    func update(_ state: RestTimerActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    func end() {
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}
