import SwiftUI
import HealthKit
import WatchKit
import FitTrackShared

enum WatchRoute: Hashable {
    case live
    case summary
    case remoteMonitoring
}

/// `HKHealthStore.startWatchApp(with:)` auf dem iPhone bringt die Watch-App
/// nur zuverlässig in den Vordergrund und mit verlängerter Hintergrund-
/// Laufzeit, wenn die App diese Konfiguration entgegennimmt und SOFORT die
/// zugehörige HKWorkoutSession startet (nicht erst später über einen
/// WatchConnectivity-Roundtrip) - siehe `WorkoutManager.beginPendingRemoteSession`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WorkoutManager.shared.beginPendingRemoteSession(activityType: workoutConfiguration.activityType)
        }
    }
}

@main
struct FitTrackWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var workoutManager = WorkoutManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                StartWorkoutView(path: $path)
                    .navigationDestination(for: WatchRoute.self) { route in
                        switch route {
                        case .live:
                            LiveWorkoutView(path: $path)
                        case .summary:
                            SummaryView(path: $path)
                        case .remoteMonitoring:
                            RemoteMonitoringView(path: $path)
                        }
                    }
            }
            .environmentObject(workoutManager)
            .environmentObject(connectivity)
            .task {
                connectivity.activate()
                try? await HealthKitManager.shared.requestAuthorization()
            }
            .onChange(of: connectivity.remoteStartRequest) { _, request in
                guard let request else { return }
                workoutManager.startRemoteMonitoring(activityType: .traditionalStrengthTraining, sessionId: request.sessionId, activityName: request.activityName)
                path = NavigationPath()
                path.append(WatchRoute.remoteMonitoring)
            }
            .onChange(of: connectivity.remoteStopRequest) { _, request in
                guard let request else { return }
                guard workoutManager.isRemoteControlled else { return }
                workoutManager.end(discard: request.discard)
            }
        }
    }
}
