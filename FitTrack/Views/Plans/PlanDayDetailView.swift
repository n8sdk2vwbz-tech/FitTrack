import SwiftUI
import SwiftData
import FitTrackShared

struct PlanDayDetailView: View {
    @Bindable var day: PlanDay
    var planName: String
    @Environment(\.modelContext) private var modelContext
    @State private var showingPicker = false
    @State private var isStartingWorkout = false
    @State private var sentToWatch = false

    var body: some View {
        List {
            Section {
                TextField("Tagesname", text: $day.name)
            }

            Section {
                Button {
                    isStartingWorkout = true
                } label: {
                    Label("Training starten", systemImage: "play.fill")
                }
                .disabled(day.itemList.isEmpty)

                Button {
                    sendToWatch()
                } label: {
                    Label(sentToWatch ? "Erneut an Apple Watch gesendet" : "An Apple Watch senden", systemImage: "applewatch")
                }
                .disabled(day.itemList.isEmpty)
            }

            Section {
                ForEach(day.itemList.sorted(by: { $0.order < $1.order })) { item in
                    PlanItemRow(item: item)
                }
                .onDelete(perform: deleteItems)
                .onMove(perform: moveItems)

                Button {
                    showingPicker = true
                } label: {
                    Label("Übung hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Übungen")
            } footer: {
                if day.itemList.count > 1 {
                    Text("Zum Umsortieren \"Bearbeiten\" antippen und die Übungen per Drag & Drop verschieben.")
                }
            }
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                addItem(for: exercise)
            }
        }
        .fullScreenCover(isPresented: $isStartingWorkout) {
            // `day`/`PlanItem` gehören zum (hier aktiven) Plans-Container -
            // `planItemContext` gibt ActiveWorkoutView eine explizite
            // Referenz darauf, um Gewichts-/Wdh.-Gedächtnis dort zu sichern.
            // Der Trainings-Verlauf selbst gehört in den History-Container,
            // der hier explizit wieder angehängt wird (sonst würde die neue
            // WorkoutSession versehentlich in den Plans-Container geschrieben).
            ActiveWorkoutView(planDay: day, planItemContext: modelContext)
                .modelContainer(AppContainers.history)
        }
    }

    /// Sendet diesen Trainingstag als "heutigen Plan" an die Apple Watch,
    /// damit er dort unabhängig vom iPhone gestartet werden kann.
    private func sendToWatch() {
        let items = day.itemList.sorted(by: { $0.order < $1.order }).map { $0.toDTO() }
        let dto = PlanDayDTO(id: UUID().uuidString, planName: planName, dayName: day.name, items: items)
        WatchConnectivityManager.shared.sendPlanDay(dto)
        sentToWatch = true
    }

    private func addItem(for exercise: Exercise) {
        let nextOrder = (day.itemList.map(\.order).max() ?? -1) + 1
        day.itemList.append(PlanItem(exerciseId: exercise.id, exerciseName: exercise.name, targetSets: 3, targetReps: 10, order: nextOrder))
        try? modelContext.save()
    }

    private func deleteItems(at offsets: IndexSet) {
        let sorted = day.itemList.sorted(by: { $0.order < $1.order })
        for index in offsets {
            if let idx = day.itemList.firstIndex(where: { $0.persistentModelID == sorted[index].persistentModelID }) {
                modelContext.delete(day.itemList[idx])
                day.itemList.remove(at: idx)
            }
        }
        try? modelContext.save()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var sorted = day.itemList.sorted(by: { $0.order < $1.order })
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, item) in sorted.enumerated() {
            item.order = index
        }
        try? modelContext.save()
    }
}

private struct PlanItemRow: View {
    @Bindable var item: PlanItem
    @FocusState private var isNotesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.exerciseName).font(.body)
            HStack(spacing: 24) {
                compactStepper(label: "Sätze", value: $item.targetSets, range: 1...10)
                compactStepper(label: "Wdh.", value: $item.targetReps, range: 1...30)
                Spacer()
            }
            HStack(spacing: 24) {
                compactStepper(label: "Aufwärmsätze", value: $item.warmupSetCount, range: 0...5)
                Spacer()
            }
            if item.warmupSetCount > 0 {
                Text("Gewicht wird beim Training automatisch aus dem Arbeitsgewicht hochgerechnet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !item.alternativeExerciseIds.isEmpty {
                Menu {
                    ForEach(item.alternativeExerciseIds.indices, id: \.self) { index in
                        Button(item.alternativeExerciseNames[index]) {
                            swapToAlternative(at: index)
                        }
                    }
                } label: {
                    Label("Alternative statt \"\(item.exerciseName)\"", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
            }

            Button {
                item.pendingWeightIncrease.toggle()
            } label: {
                Label(
                    item.pendingWeightIncrease ? "Gewicht wird nächstes Mal gesteigert" : "Gewicht nächstes Mal steigern",
                    systemImage: item.pendingWeightIncrease ? "checkmark.circle.fill" : "arrow.up.circle"
                )
                .font(.caption)
                .foregroundStyle(item.pendingWeightIncrease ? .green : .accentColor)
            }
            .buttonStyle(.plain)

            TextField("Notiz zu dieser Übung (optional)", text: $item.notes, axis: .vertical)
                .font(.caption)
                .lineLimit(1...3)
                .focused($isNotesFocused)
                .toolbar {
                    // Mehrzeiliges TextField (axis: .vertical) schließt die
                    // Tastatur nicht per Return - ohne diese Taste gäbe es
                    // sonst keine Möglichkeit, sie wieder wegzuklappen.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fertig") { isNotesFocused = false }
                    }
                }
        }
        .padding(.vertical, 4)
    }

    /// Tauscht die Übung gegen die gewählte Alternative - die bisherige
    /// Übung rückt an deren Stelle in die Alternativen-Liste, damit man
    /// jederzeit wieder zurückwechseln kann.
    private func swapToAlternative(at index: Int) {
        let newId = item.alternativeExerciseIds[index]
        let newName = item.alternativeExerciseNames[index]
        var ids = item.alternativeExerciseIds
        var names = item.alternativeExerciseNames
        ids[index] = item.exerciseId
        names[index] = item.exerciseName
        item.exerciseId = newId
        item.exerciseName = newName
        item.alternativeExerciseIds = ids
        item.alternativeExerciseNames = names
    }

    private func compactStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text("\(label) \(value.wrappedValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }
}
