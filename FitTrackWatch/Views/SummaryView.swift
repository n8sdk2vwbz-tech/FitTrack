import SwiftUI
import FitTrackShared

struct SummaryView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Workout beendet").font(.headline)

                if let summary = workoutManager.lastSummary {
                    let minutes = Int(summary.endDate.timeIntervalSince(summary.startDate) / 60)
                    Text("\(minutes) min")
                    if let kcal = summary.totalEnergyBurnedKcal {
                        Text("\(Int(kcal)) kcal")
                    }
                    if let hr = summary.averageHeartRate {
                        Text("Ø \(Int(hr)) bpm")
                    }
                    Text("An iPhone gesendet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Fertig") {
                    path = NavigationPath()
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(true)
    }
}
