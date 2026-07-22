import Foundation

#if canImport(ActivityKit) && canImport(AppIntents)
import AppIntents

/// Vom "Satz erledigt"-Button in der Live Activity ausgelöst (Sperrbildschirm
/// & Dynamic Island, siehe `FitTrackWidgets/RestTimerLiveActivityWidget.swift`).
/// `LiveActivityIntent` (statt eines einfachen `AppIntent`) garantiert, dass
/// `perform()` im Prozess dieser App läuft (und sie bei Bedarf im Hintergrund
/// startet) - genau das macht `LiveActivityActionRelay` direkt erreichbar,
/// ohne App Groups oder sonstige Cross-Process-Übertragung.
@available(iOS 17.0, *)
public struct CompleteSetLiveActivityIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Satz erledigt"

    public init() {}

    public func perform() async throws -> some IntentResult {
        await LiveActivityActionRelay.shared.requestCompleteSet()
        return .result()
    }
}

/// Vom Wdh.-Stepper (+/-) in der Live Activity ausgelöst - passt die
/// Wiederholungen des nächsten noch offenen Satzes an, siehe
/// `ActiveWorkoutView.adjustNextPendingSetReps(by:)`.
@available(iOS 17.0, *)
public struct AdjustNextSetRepsIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Wiederholungen anpassen"

    @Parameter(title: "Änderung")
    public var delta: Int

    public init() {
        self.delta = 0
    }

    public init(delta: Int) {
        self.delta = delta
    }

    public func perform() async throws -> some IntentResult {
        await LiveActivityActionRelay.shared.requestRepsAdjustment(delta: delta)
        return .result()
    }
}
#endif
