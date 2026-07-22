import Foundation

#if canImport(ActivityKit)
/// Verbindet die interaktiven Buttons der Live Activity (siehe
/// `CompleteSetLiveActivityIntent`/`AdjustNextSetRepsIntent` - laufen dank
/// `LiveActivityIntent` garantiert im Prozess dieser App, keine
/// Cross-Process-Übertragung nötig) mit der laufenden `ActiveWorkoutView`.
/// Dieselbe Beobachtungs-Idee wie bei `WatchConnectivityManager`, hier aber
/// rein intra-process. Jeder Aufruf erzeugt einen frischen Bezeichner (siehe
/// `RepsAdjustmentEvent`/UUID) - `ActiveWorkoutView` reagiert per
/// `.onChange(of:)`, das nur bei tatsächlicher Wertänderung auslöst; zwei
/// Tastendrücke mit sonst identischem Inhalt (z.B. zweimal "Satz erledigt")
/// würden sonst nach dem ersten Mal nie wieder erkannt.
@available(iOS 16.1, *)
public final class LiveActivityActionRelay: ObservableObject {
    public static let shared = LiveActivityActionRelay()

    public struct RepsAdjustmentEvent: Equatable {
        public let id: UUID
        public let delta: Int

        public init(delta: Int) {
            self.id = UUID()
            self.delta = delta
        }
    }

    @Published public var completeSetRequested: UUID?
    @Published public var repsAdjustment: RepsAdjustmentEvent?

    private init() {}

    @MainActor
    public func requestCompleteSet() {
        completeSetRequested = UUID()
    }

    @MainActor
    public func requestRepsAdjustment(delta: Int) {
        repsAdjustment = RepsAdjustmentEvent(delta: delta)
    }
}
#endif
