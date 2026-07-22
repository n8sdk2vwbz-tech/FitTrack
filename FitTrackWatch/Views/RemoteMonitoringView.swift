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
            // Puls und Pausen-Timer bewusst als Erstes, ohne einleitendes Icon/
            // Beschriftung davor - sollen ohne Scrollen sofort sichtbar sein,
            // das ist die während des Trainings wichtigste Information.
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("\(Int(workoutManager.heartRate))")
                        .font(.system(.largeTitle, design: .rounded))
                        .foregroundStyle(.red)
                    Text("bpm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if workoutManager.isRestTimerActive {
                    Label("\(Int(workoutManager.restElapsedSeconds))s Pause", systemImage: "heart.text.square")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }

                Button {
                    workoutManager.completeSetRemotely()
                } label: {
                    Label("Satz erledigt", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)

                Text(workoutManager.remoteActivityName ?? "Training")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(Int(workoutManager.activeEnergyKcal)) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    workoutManager.end()
                } label: {
                    Label("Beenden", systemImage: "stop.fill")
                }
                .font(.caption2)
            }
            .padding(.horizontal, 4)
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: workoutManager.didFinish) { _, finished in
            print("🔧 RestTimerDebug: RemoteMonitoringView onChange didFinish=\(finished)")
            guard finished else { return }
            path = NavigationPath()
        }
    }
}
