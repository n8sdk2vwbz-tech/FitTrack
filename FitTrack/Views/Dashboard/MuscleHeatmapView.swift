import SwiftUI
import FitTrackShared

struct MuscleHeatmapView: View {
    let statuses: [MuscleGroup: MuscleLoadStatus]
    let readiness: ReadinessResult?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    private var trainableMuscles: [MuscleGroup] {
        MuscleGroup.allCases.filter { $0 != .cardio }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Muskelbelastung")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(trainableMuscles) { muscle in
                    if let status = statuses[muscle] {
                        NavigationLink {
                            MuscleDetailView(status: status, readiness: readiness)
                        } label: {
                            MuscleCell(status: status)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MuscleCell: View {
    let status: MuscleLoadStatus

    var body: some View {
        VStack(spacing: 4) {
            Text(status.muscle.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(status.fatigueLevel.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(8)
        .background(status.fatigueLevel.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(status.fatigueLevel.color, lineWidth: 1.5))
    }
}

struct MuscleDetailView: View {
    let status: MuscleLoadStatus
    let readiness: ReadinessResult?

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: status.fatigueLevel.displayName)
                LabeledContent("ACWR", value: String(format: "%.2f", status.acwr))
                if let days = status.daysSinceLastTrained {
                    LabeledContent("Zuletzt trainiert", value: "vor \(days) Tag(en)")
                } else {
                    LabeledContent("Zuletzt trainiert", value: "keine Daten")
                }
            }

            if let readiness {
                Section("Empfehlung") {
                    Text(RecoveryEngine.recommendation(for: status, readiness: readiness))
                }
            }

            Section("Übungen für \(status.muscle.displayName)") {
                ForEach(ExerciseLibrary.exercises(for: status.muscle)) { exercise in
                    NavigationLink(exercise.name) {
                        ExerciseDetailView(exercise: exercise)
                    }
                }
            }
        }
        .navigationTitle(status.muscle.displayName)
    }
}
