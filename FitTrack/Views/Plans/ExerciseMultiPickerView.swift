import SwiftUI
import FitTrackShared

/// Mehrfachauswahl von Übungen, z.B. um sie beim Plan-Generator gezielt
/// auszuschließen (Gerät im Gym nicht verfügbar, Übung nicht gemocht o.ä.).
struct ExerciseMultiPickerView: View {
    @Binding var selectedIds: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Exercise] {
        ExerciseLibrary.all
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    if selectedIds.contains(exercise.id) {
                        selectedIds.remove(exercise.id)
                    } else {
                        selectedIds.insert(exercise.id)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.primaryMuscles.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedIds.contains(exercise.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Übung suchen")
            .navigationTitle("Übungen ausschließen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
