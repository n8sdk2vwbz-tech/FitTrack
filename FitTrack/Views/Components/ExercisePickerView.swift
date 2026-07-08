import SwiftUI
import FitTrackShared

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedMuscle: MuscleGroup?

    private var filtered: [Exercise] {
        ExerciseLibrary.all
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .filter { selectedMuscle == nil || $0.allMuscles.contains(selectedMuscle!) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(exercise.name).foregroundStyle(.primary)
                        Text(exercise.primaryMuscles.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Übung suchen")
            .navigationTitle("Übung wählen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            selectedMuscle = nil
                        } label: {
                            if selectedMuscle == nil {
                                Label("Alle Muskelgruppen", systemImage: "checkmark")
                            } else {
                                Text("Alle Muskelgruppen")
                            }
                        }
                        Divider()
                        ForEach(MuscleGroup.allCases) { muscle in
                            Button {
                                selectedMuscle = muscle
                            } label: {
                                if selectedMuscle == muscle {
                                    Label(muscle.displayName, systemImage: "checkmark")
                                } else {
                                    Text(muscle.displayName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedMuscle == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
        }
    }
}
