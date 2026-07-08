import SwiftUI
import SwiftData
import FitTrackShared

/// Fragebogen-gestützte, lokale Trainingsplan-Erstellung (siehe
/// `PlanGenerator` im Shared-Package) - komplett offline, ohne externe KI.
struct GeneratePlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var onCreated: (TrainingPlan) -> Void

    @State private var splitType: SplitType = .upperLower
    @State private var daysPerWeek = 4
    @State private var experienceLevel: ExperienceLevel = .intermediate
    @State private var goal: TrainingGoal = .hypertrophy
    @State private var sessionDuration: SessionDuration = .medium
    @State private var selectedEquipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .bodyweight]
    @State private var excludedMuscles: Set<MuscleGroup> = []

    private let equipmentOptions: [Equipment] = [.barbell, .dumbbell, .kettlebell, .machine, .cable, .band, .bodyweight]
    private let muscleOptions = MuscleGroup.allCases.filter { $0 != .cardio }

    var body: some View {
        NavigationStack {
            Form {
                Section("Split") {
                    Picker("Trainingsaufteilung", selection: $splitType) {
                        ForEach(SplitType.allCases) { split in
                            Text(split.displayName).tag(split)
                        }
                    }
                    Text(splitType.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper("Trainingstage/Woche: \(daysPerWeek)", value: $daysPerWeek, in: 2...7)
                }

                Section("Ziel & Erfahrung") {
                    Picker("Ziel", selection: $goal) {
                        ForEach(TrainingGoal.allCases) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }
                    Picker("Erfahrung", selection: $experienceLevel) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    Picker("Trainingsdauer", selection: $sessionDuration) {
                        ForEach(SessionDuration.allCases) { duration in
                            Text(duration.displayName).tag(duration)
                        }
                    }
                }

                Section {
                    ForEach(equipmentOptions) { equipment in
                        Toggle(equipment.displayName, isOn: Binding(
                            get: { selectedEquipment.contains(equipment) },
                            set: { isOn in
                                if isOn { selectedEquipment.insert(equipment) } else { selectedEquipment.remove(equipment) }
                            }
                        ))
                    }
                } header: {
                    Text("Verfügbares Equipment")
                } footer: {
                    Text("Körpergewichtsübungen sind immer verfügbar.")
                }

                Section {
                    ForEach(muscleOptions) { muscle in
                        Toggle(muscle.displayName, isOn: Binding(
                            get: { excludedMuscles.contains(muscle) },
                            set: { isOn in
                                if isOn { excludedMuscles.insert(muscle) } else { excludedMuscles.remove(muscle) }
                            }
                        ))
                    }
                } header: {
                    Text("Einschränkungen (optional)")
                } footer: {
                    Text("Ausgewählte Muskelgruppen werden bei der Übungsauswahl gemieden, z.B. bei Verletzungen.")
                }
            }
            .navigationTitle("Plan erstellen lassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") { generate() }
                        .disabled(selectedEquipment.isEmpty)
                }
            }
        }
    }

    private func generate() {
        let input = PlanGeneratorInput(
            splitType: splitType,
            daysPerWeek: daysPerWeek,
            experienceLevel: experienceLevel,
            goal: goal,
            availableEquipment: selectedEquipment,
            sessionDuration: sessionDuration,
            excludedMuscles: excludedMuscles
        )
        let generatedDays = PlanGenerator.generate(from: input)

        let days: [PlanDay] = generatedDays.enumerated().map { dayIndex, generatedDay in
            let items: [PlanItem] = generatedDay.items.enumerated().map { itemIndex, item in
                PlanItem(
                    exerciseId: item.exercise.id,
                    exerciseName: item.exercise.name,
                    targetSets: item.targetSets,
                    targetReps: item.targetReps,
                    warmupSetCount: item.warmupSetCount,
                    order: itemIndex
                )
            }
            return PlanDay(name: generatedDay.name, order: dayIndex, items: items)
        }

        let plan = TrainingPlan(name: "\(splitType.displayName)-Plan", days: days)
        modelContext.insert(plan)
        try? modelContext.save()
        onCreated(plan)
        dismiss()
    }
}
