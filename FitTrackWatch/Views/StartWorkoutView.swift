import SwiftUI
import HealthKit
import FitTrackShared

struct StartWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("ReadyLift").font(.headline)

                if let plan = connectivity.receivedPlanDay {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.planName).font(.caption).foregroundStyle(.secondary)
                        Text(plan.dayName).font(.subheadline).fontWeight(.semibold)
                        Text("\(plan.items.count) Übungen").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    Button {
                        start(activityType: .traditionalStrengthTraining, planDay: plan)
                    } label: {
                        Label("Plan starten", systemImage: "play.fill")
                    }
                    .tint(.green)
                }

                Button {
                    start(activityType: .traditionalStrengthTraining, planDay: nil)
                } label: {
                    Label("Kraft – Schnellstart", systemImage: "figure.strengthtraining.traditional")
                }

                Text("Für Laufen, Radfahren & Co. die Apple Watch Workout-App nutzen – die Einheit erscheint danach automatisch in ReadyLift.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    private func start(activityType: HKWorkoutActivityType, planDay: PlanDayDTO?) {
        workoutManager.startWorkout(activityType: activityType, planDay: planDay)
        path.append(WatchRoute.live)
    }
}
