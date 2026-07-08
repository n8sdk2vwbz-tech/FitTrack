import SwiftUI
import SwiftData
import FitTrackShared

private struct DraftSet: Identifiable {
    let id = UUID()
    var reps: Int = 10
    var weightKg: Double = 20
    var isWarmup: Bool = false
}

private struct DraftExercise: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var sets: [DraftSet] = [DraftSet()]
}

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var activityName = "Krafttraining"
    @State private var date = Date()
    @State private var durationMinutes = 45
    @State private var draftExercises: [DraftExercise] = []
    @State private var showingPicker = false
    @State private var isSaving = false
    @State private var perceivedExertion: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $activityName)
                    DatePicker("Datum", selection: $date)
                    Stepper("Dauer: \(durationMinutes) min", value: $durationMinutes, in: 5...240, step: 5)
                }

                Section("Übungen") {
                    ForEach($draftExercises) { $draft in
                        DisclosureGroup(draft.exercise.name) {
                            ForEach($draft.sets) { $set in
                                HStack(spacing: 6) {
                                    IntAdjuster(value: $set.reps)
                                    Text("Wdh.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                    Spacer(minLength: 4)
                                    WeightAdjuster(weightKg: $set.weightKg)
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete { offsets in draft.sets.remove(atOffsets: offsets) }

                            Button {
                                draft.sets.append(DraftSet())
                            } label: {
                                Label("Satz hinzufügen", systemImage: "plus")
                            }
                        }
                    }
                    .onDelete { offsets in draftExercises.remove(atOffsets: offsets) }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                    }
                }

                Section {
                    EffortRatingBars(rating: $perceivedExertion)
                        .frame(height: 70)
                        .padding(.vertical, 4)
                    if let perceivedExertion {
                        Text("\(perceivedExertion)/10 · \(effortLabel(perceivedExertion))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Anstrengung (optional)")
                } footer: {
                    Text("Fließt in die Trainingslast und deinen Bereitschafts-Score ein.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Workout loggen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") { Task { await save() } }
                            .disabled(draftExercises.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    draftExercises.append(DraftExercise(exercise: exercise))
                }
            }
        }
    }

    /// Speichert das nachgetragene Workout lokal und zusätzlich als HKWorkout
    /// in HealthKit, damit es auch in der Apple Health/Fitness-App erscheint.
    private func save() async {
        isSaving = true
        let entries = draftExercises.enumerated().map { index, draft -> ExerciseEntry in
            let sets = draft.sets.enumerated().map { setIndex, set in
                SetEntry(reps: set.reps, weightKg: set.weightKg, isWarmup: set.isWarmup, order: setIndex)
            }
            return ExerciseEntry(exerciseId: draft.exercise.id, exerciseName: draft.exercise.name, order: index, sets: sets)
        }

        let durationSeconds = Double(durationMinutes * 60)
        let endDate = date.addingTimeInterval(durationSeconds)
        let workout = await HealthKitManager.shared.saveWorkoutBestEffort(
            activityType: .traditionalStrengthTraining,
            start: date,
            end: endDate,
            totalEnergyBurnedKcal: nil,
            averageHeartRate: nil
        )

        let session = WorkoutSession(
            date: date,
            activityName: activityName,
            durationSeconds: durationSeconds,
            source: .iphone,
            healthKitWorkoutUUID: workout?.uuid.uuidString,
            perceivedExertion: perceivedExertion,
            entries: entries
        )
        modelContext.insert(session)
        try? modelContext.save()
        dismiss()
    }
}
