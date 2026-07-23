import SwiftUI
import FitTrackShared

struct LiveWorkoutView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @Binding var path: NavigationPath
    @State private var reps = 10
    @State private var weightKg = 20.0

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    metric(value: timeString(workoutManager.elapsedSeconds), label: "Zeit")
                    metric(value: "\(Int(workoutManager.heartRate))", label: "bpm")
                    metric(value: "\(Int(workoutManager.activeEnergyKcal))", label: "kcal")
                }

                if workoutManager.isRestTimerActive {
                    Label("Pause: \(Int(workoutManager.restElapsedSeconds))s", systemImage: "heart.text.square")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if let target = workoutManager.currentRestTargetHeartRate {
                        Text("Ziel: \(Int(target)) bpm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ziel: fixe Wartezeit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let item = workoutManager.currentPlanItem {
                    Divider()
                    VStack(spacing: 4) {
                        Text(item.exerciseName).font(.subheadline).fontWeight(.semibold)
                        Text("Ziel: \(item.targetSets) x \(item.targetReps)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Geloggt: \(workoutManager.currentSetCount) Sätze")
                            .font(.caption2)
                    }

                    Stepper("Wdh.: \(reps)", value: $reps, in: 1...50)
                        .font(.caption)
                    Stepper("\(weightKg, specifier: "%.1f") kg", value: $weightKg, in: 0...300, step: 1.25)
                        .font(.caption)

                    Button {
                        workoutManager.logSet(reps: reps, weightKg: weightKg)
                    } label: {
                        Label("Satz loggen", systemImage: "checkmark")
                    }
                    .tint(.blue)

                    Button("Nächste Übung") {
                        workoutManager.nextExercise()
                    }
                    .font(.caption)
                }

                Divider()

                HStack {
                    Button {
                        workoutManager.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    Button {
                        workoutManager.resume()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    Button {
                        workoutManager.end()
                        path.append(WatchRoute.summary)
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func metric(value: String, label: String) -> some View {
        VStack {
            Text(value).font(.system(.title3, design: .rounded)).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
