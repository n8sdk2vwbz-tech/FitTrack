import SwiftUI
import FitTrackShared

/// Wird angezeigt, wenn das iPhone die Watch angefordert hat, die Herzfrequenz
/// für ein dort gestartetes Training zu messen. Die Watch führt dafür im
/// Hintergrund dieselbe HKWorkoutSession wie bei einem lokal gestarteten
/// Training aus, zeigt hier aber nur die Live-Werte statt der Satz-Erfassung.
struct RemoteMonitoringView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text(workoutManager.remoteActivityName ?? "Training")
                    .font(.headline)
                Text("Gesteuert vom iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 2) {
                    Text("\(Int(workoutManager.heartRate))")
                        .font(.system(.largeTitle, design: .rounded))
                        .foregroundStyle(.red)
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(workoutManager.activeEnergyKcal)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    workoutManager.end()
                } label: {
                    Label("Beenden", systemImage: "stop.fill")
                }
                .font(.caption)
            }
            .padding(.horizontal, 4)
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: workoutManager.didFinish) { _, finished in
            guard finished else { return }
            path = NavigationPath()
        }
    }
}
