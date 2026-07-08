import SwiftUI
import SwiftData
import Charts
import FitTrackShared

struct ExerciseDetailView: View {
    let exercise: Exercise

    @Query(sort: \WorkoutSession.date, order: .forward) private var allSessions: [WorkoutSession]

    private var history: [(date: Date, topWeight: Double, volume: Double)] {
        WorkoutSession.history(forExerciseId: exercise.id, in: allSessions)
    }

    var body: some View {
        List {
            Section("Anleitung") {
                Text(exercise.instructions)
            }

            Section("Details") {
                LabeledContent("Kategorie", value: exercise.category.displayName)
                LabeledContent("Gerät", value: exercise.equipment.displayName)
            }

            Section("Primäre Muskeln") {
                ForEach(exercise.primaryMuscles) { muscle in
                    Text(muscle.displayName)
                }
            }

            if !exercise.secondaryMuscles.isEmpty {
                Section("Sekundäre Muskeln") {
                    ForEach(exercise.secondaryMuscles) { muscle in
                        Text(muscle.displayName)
                    }
                }
            }

            if !history.isEmpty {
                Section("Fortschritt (Top-Satz-Gewicht)") {
                    Chart(history, id: \.date) { point in
                        LineMark(x: .value("Datum", point.date), y: .value("kg", point.topWeight))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Datum", point.date), y: .value("kg", point.topWeight))
                    }
                    .frame(height: 160)
                    .padding(.vertical, 4)
                }

                Section("Letzte Einheiten") {
                    ForEach(history.reversed().prefix(5), id: \.date) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\(point.topWeight, specifier: "%.1f") kg · Vol. \(Int(point.volume))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
