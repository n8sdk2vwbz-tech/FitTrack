import SwiftUI
import SwiftData
import FitTrackShared

struct ExerciseLibraryView: View {
    @Query private var sessions: [WorkoutSession]
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory?
    @State private var selectedMuscle: MuscleGroup?
    @State private var onlyRecentlyTrained = false

    private var recentlyTrainedExerciseIds: Set<String> {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) else { return [] }
        return Set(
            sessions
                .filter { $0.date >= cutoff }
                .flatMap { $0.entryList.map(\.exerciseId) }
        )
    }

    private var filtered: [Exercise] {
        let trainedIds = onlyRecentlyTrained ? recentlyTrainedExerciseIds : nil
        return ExerciseLibrary.all.filter { exercise in
            (searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText))
            && (selectedCategory == nil || exercise.category == selectedCategory)
            && (selectedMuscle == nil || exercise.allMuscles.contains(selectedMuscle!))
            && (trainedIds == nil || trainedIds!.contains(exercise.id))
        }
        .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            filterChip(title: "Alle", isSelected: selectedCategory == nil) { selectedCategory = nil }
                            ForEach(ExerciseCategory.allCases) { category in
                                filterChip(title: category.displayName, isSelected: selectedCategory == category) {
                                    selectedCategory = selectedCategory == category ? nil : category
                                }
                            }
                        }
                    }
                    .listRowSeparator(.hidden)

                    Menu {
                        Button("Alle Muskelgruppen") { selectedMuscle = nil }
                        ForEach(MuscleGroup.allCases) { muscle in
                            Button(muscle.displayName) { selectedMuscle = muscle }
                        }
                    } label: {
                        Label(selectedMuscle?.displayName ?? "Muskelgruppe filtern", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Toggle("Nur in den letzten 30 Tagen trainiert", isOn: $onlyRecentlyTrained)
                        .font(.subheadline)
                }

                Section {
                    ForEach(filtered) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name).font(.body)
                                Text(exercise.primaryMuscles.map(\.displayName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("\(filtered.count) Übungen")
                } footer: {
                    if onlyRecentlyTrained && filtered.isEmpty {
                        Text("Keine Übung wurde in den letzten 30 Tagen trainiert.")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Übung suchen")
            .navigationTitle("Übungsbibliothek")
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}
