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

/// Ergänzt eine bestehende Trainingseinheit nachträglich um Übungen/Sätze -
/// z.B. für ein aus Health importiertes Training, das (mangels Satz-/
/// Wiederholungsdaten) sonst nicht zur Muskel-/Trainingslast beiträgt.
/// Ändert bewusst NICHT Datum/Dauer/Kalorien/Herzfrequenz oder die
/// `healthKitWorkoutUUID` der Session - nur die Übungsliste wird ergänzt,
/// damit ein erneuter Health-Import sie weiterhin als bereits bekannt
/// erkennt, statt sie als Duplikat neu anzulegen.
struct EditWorkoutExercisesView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draftExercises: [DraftExercise] = []
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            Form {
                if !session.entryList.isEmpty {
                    Section("Bereits erfasst") {
                        ForEach(session.entryList.sorted(by: { $0.order < $1.order })) { entry in
                            Text(entry.summaryText == "–" ? entry.exerciseName : "\(entry.exerciseName): \(entry.summaryText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Übungen nachtragen") {
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
            }
            .keyboardDoneButton()
            .navigationTitle("Übungen nachtragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(draftExercises.isEmpty)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    draftExercises.append(DraftExercise(exercise: exercise))
                }
            }
        }
    }

    private func save() {
        let startOrder = (session.entryList.map(\.order).max() ?? -1) + 1
        let newEntries = draftExercises.enumerated().map { index, draft -> ExerciseEntry in
            let sets = draft.sets.enumerated().map { setIndex, set in
                SetEntry(reps: set.reps, weightKg: set.weightKg, isWarmup: set.isWarmup, order: setIndex)
            }
            return ExerciseEntry(exerciseId: draft.exercise.id, exerciseName: draft.exercise.name, order: startOrder + index, sets: sets)
        }
        session.entryList.append(contentsOf: newEntries)
        try? modelContext.save()
        dismiss()
    }
}
