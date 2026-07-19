import SwiftUI
import SwiftData
import FitTrackShared

private struct LiveSet: Identifiable {
    let id = UUID()
    var reps: Int
    var weightKg: Double
    var isWarmup: Bool = false
    /// Abgehakt = tatsächlich durchgeführt. Nur abgehakte Sätze zählen für
    /// die gespeicherte Einheit (Verlauf, Volumen, Muskelbelastung).
    var isCompleted: Bool = false
}

private struct LiveExercise: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var targetReps: Int
    var sets: [LiveSet]
    /// Referenz auf den ursprünglichen Plan-Eintrag (nil bei spontan während
    /// des Trainings hinzugefügten Übungen) - wird nach dem Training mit dem
    /// zuletzt genutzten Gewicht/Wdh. aktualisiert, damit dieselbe Übung an
    /// dieser Stelle im Plan beim nächsten Mal automatisch vorausgefüllt ist.
    var planItem: PlanItem?
}

/// Geführtes Live-Training direkt auf dem iPhone: startet einen laufenden Timer,
/// füllt Übungen aus einem Trainingsplan vor (inkl. automatisch berechneter
/// Aufwärmsätze und der zuletzt für genau diesen Plan-Eintrag genutzten
/// Gewichte) und speichert das Ergebnis am Ende als `WorkoutSession`. Fordert
/// dabei die Apple Watch per WatchConnectivity an, für die Dauer des
/// Trainings die Herzfrequenz zu messen (HealthKit erlaubt Live-Sensordaten
/// nur über eine HKWorkoutSession auf der Watch selbst, siehe `WorkoutManager`
/// auf der Watch).
struct ActiveWorkoutView: View {
    let planDay: PlanDay?
    /// Explizite Referenz auf den Plans-Container (der `planDay`/`PlanItem`
    /// gehören), um dort das Gewichts-/Wdh.-Gedächtnis zu sichern. `nil` bei
    /// spontanen Trainings ohne Plan. `@Environment(\.modelContext)` reicht
    /// hierfür nicht, da diese View für den Trainings-Verlauf explizit auf
    /// den History-Container umgehängt wird (siehe `PlanDayDetailView`).
    var planItemContext: ModelContext? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var allSessions: [WorkoutSession]
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    @State private var sessionId = UUID().uuidString
    @State private var startDate = Date()
    @State private var now = Date()
    @State private var liveExercises: [LiveExercise] = []
    @State private var showingPicker = false
    @State private var isFinishing = false

    @State private var latestHeartRate: Double?
    @State private var heartRateSamples: [Double] = []
    @State private var remoteEnergyKcal: Double?
    @State private var remoteAvgHeartRate: Double?
    @State private var remoteHealthKitUUID: String?
    @State private var startRequestAttempts = 0
    @State private var completedSession: WorkoutSession?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedText: String {
        let seconds = max(0, Int(now.timeIntervalSince(startDate)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var hasCompletedAnySet: Bool {
        liveExercises.contains { $0.sets.contains { $0.isCompleted } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label("Dauer", systemImage: "timer")
                        Spacer()
                        Text(elapsedText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Herzfrequenz", systemImage: "heart.fill")
                        Spacer()
                        if let latestHeartRate {
                            Text("\(Int(latestHeartRate)) bpm")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text(connectivity.isCounterpartReachable ? "Wird verbunden…" : "Watch-App öffnen zum Verbinden")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach($liveExercises) { $live in
                    Section {
                        if let last = WorkoutSession.mostRecentEntry(forExerciseId: live.exercise.id, in: allSessions) {
                            Text("Letztes Mal: \(last.summaryText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = live.planItem?.notes, !notes.isEmpty {
                            Label(notes, systemImage: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if live.exercise.loadType != .external {
                            Text("Eingegebenes Gewicht = \(live.exercise.loadType.displayName), wird mit deinem Körpergewicht aus Health verrechnet.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let planItem = live.planItem {
                            Button {
                                planItem.pendingWeightIncrease.toggle()
                            } label: {
                                Label(
                                    planItem.pendingWeightIncrease ? "Gewicht wird nächstes Mal gesteigert" : "Gewicht nächstes Mal steigern",
                                    systemImage: planItem.pendingWeightIncrease ? "checkmark.circle.fill" : "arrow.up.circle"
                                )
                                .font(.caption)
                                .foregroundStyle(planItem.pendingWeightIncrease ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(Array($live.sets.enumerated()), id: \.element.id) { index, $set in
                            HStack(spacing: 6) {
                                Button {
                                    set.isCompleted.toggle()
                                } label: {
                                    Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(set.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(setLabel(index: index, sets: live.sets))
                                    .font(.caption2)
                                    .foregroundStyle(set.isWarmup ? .orange : .secondary)
                                    .fixedSize()
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
                        .onDelete { offsets in live.sets.remove(atOffsets: offsets) }

                        Button {
                            let lastWeight = live.sets.last?.weightKg ?? 0
                            live.sets.append(LiveSet(reps: live.targetReps, weightKg: lastWeight))
                        } label: {
                            Label("Satz hinzufügen", systemImage: "plus")
                        }
                    } header: {
                        Text(live.exercise.name)
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(planDay?.name ?? "Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isFinishing {
                        ProgressView()
                    } else {
                        Button("Beenden") {
                            Task { await finishAsync() }
                        }
                        .disabled(!hasCompletedAnySet)
                    }
                }
            }
            .onReceive(timer) { value in now = value }
            .onAppear(perform: setupFromPlanIfNeeded)
            .task {
                // `sendMessage` allein schlägt lautlos fehl, wenn die Watch-App
                // gerade nicht läuft. `startWatchApp` startet sie gezielt und
                // lässt sie dort sofort die HKWorkoutSession beginnen.
                _ = await HealthKitManager.shared.startWatchApp(activityType: .traditionalStrengthTraining)
                sendStartRequest()
            }
            .onChange(of: connectivity.isCounterpartReachable) { _, reachable in
                // Die Watch war beim ersten Sendeversuch evtl. noch nicht als
                // erreichbar erkannt (kurz nach App-Start) - sobald sie es wird,
                // erneut senden, solange noch keine Herzfrequenz eingetroffen ist.
                guard reachable else { return }
                sendStartRequest()
            }
            .onChange(of: connectivity.heartRateUpdate) { _, update in
                guard let update, update.sessionId == sessionId else { return }
                latestHeartRate = update.bpm
                heartRateSamples.append(update.bpm)
            }
            .onChange(of: connectivity.remoteWorkoutResult) { _, result in
                guard let result, result.sessionId == sessionId else { return }
                remoteEnergyKcal = result.totalEnergyBurnedKcal
                remoteAvgHeartRate = result.averageHeartRate
                remoteHealthKitUUID = result.healthKitWorkoutUUID
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView { exercise in
                    liveExercises.append(LiveExercise(exercise: exercise, targetReps: 10, sets: [LiveSet(reps: 10, weightKg: 0)], planItem: nil))
                }
            }
            .fullScreenCover(item: $completedSession, onDismiss: { dismiss() }) { session in
                RateEffortView(session: session)
            }
        }
        .interactiveDismissDisabled()
    }

    /// Zeigt Aufwärmsätze als "W1, W2, …" und Arbeitssätze als fortlaufende
    /// Nummer 1, 2, … (unabhängig von evtl. vorangestellten Aufwärmsätzen).
    private func setLabel(index: Int, sets: [LiveSet]) -> String {
        if sets[index].isWarmup {
            let warmupIndex = sets[..<index].filter(\.isWarmup).count + 1
            return "W\(warmupIndex)"
        }
        let workIndex = sets[..<index].filter { !$0.isWarmup }.count + 1
        return "\(workIndex)."
    }

    private func setupFromPlanIfNeeded() {
        guard liveExercises.isEmpty, let planDay else { return }
        liveExercises = planDay.itemList.sorted(by: { $0.order < $1.order }).map { item in
            // Bewusst KEIN Fallback auf die global letzte Leistung dieser
            // Übung (die könnte aus einem anderen Plan oder Trainingstag
            // stammen) - jeder Plan-Eintrag führt sein eigenes, unabhängiges
            // Gewichts-Gedächtnis. Wurde dieser Eintrag noch nie ausgeführt,
            // startet er bei 0 und muss manuell befüllt werden.
            let rememberedWeight = item.targetWeightKg ?? 0
            // Wurde eine Gewichtssteigerung vorgemerkt, hier einmalig einen
            // Plattenschritt draufschlagen - `pendingWeightIncrease` wird erst
            // in `updatePlanMemory` nach Abschluss dieser Einheit zurückgesetzt,
            // ein Abbruch ohne Abschluss lässt die Vormerkung also bestehen.
            let workWeight = (item.pendingWeightIncrease && rememberedWeight > 0)
                ? roundToRealisticWeight(rememberedWeight + 2.5)
                : rememberedWeight

            var sets: [LiveSet] = warmupSets(workWeight: workWeight, workReps: item.targetReps, count: item.warmupSetCount).map { warmup in
                LiveSet(reps: warmup.reps, weightKg: warmup.weight, isWarmup: true)
            }
            sets += (0..<max(item.targetSets, 1)).map { _ in
                LiveSet(reps: item.targetReps, weightKg: workWeight, isWarmup: false)
            }

            let exercise = ExerciseLibrary.byId[item.exerciseId] ?? Exercise(
                id: item.exerciseId,
                name: item.exerciseName,
                category: .strength,
                equipment: .none,
                primaryMuscles: [],
                secondaryMuscles: [],
                instructions: ""
            )
            return LiveExercise(exercise: exercise, targetReps: item.targetReps, sets: sets, planItem: item)
        }
    }

    /// Berechnet Aufwärmsätze als ansteigende Gewichts-Rampe von ca. 40% bis
    /// 85% des Arbeitsgewichts (bei nur einem Aufwärmsatz 50%), mit dazu
    /// passend ABNEHMENDER Wiederholungszahl: großzügig beim leichten
    /// Aktivierungssatz, nur noch sehr wenige kurz vor dem Arbeitsgewicht -
    /// statt bei jedem Aufwärmsatz identisch viele Wiederholungen wie im
    /// Arbeitssatz vorzuschlagen.
    private func warmupSets(workWeight: Double, workReps: Int, count: Int) -> [(weight: Double, reps: Int)] {
        guard count > 0 else { return [] }
        guard workWeight > 0 else { return Array(repeating: (0, workReps), count: count) }
        guard count > 1 else { return [(roundToRealisticWeight(workWeight * 0.5), max(workReps, 6))] }

        let generousReps = max(workReps + 2, 6)
        return (0..<count).map { i in
            let fraction = 0.4 + 0.45 * Double(i) / Double(count - 1)
            let weight = roundToRealisticWeight(workWeight * fraction)
            let rampFraction = Double(i) / Double(count - 1) // 0 = leichtester, 1 = schwerster Aufwärmsatz
            let reps = generousReps - Int((Double(generousReps - 2) * rampFraction).rounded())
            return (weight, max(2, reps))
        }
    }

    /// Rundet auf ein in Fitnessstudios übliches Plattenschritt-Raster
    /// (2,5 kg), damit z.B. nie "18,836 kg" statt "17,5 kg" vorgeschlagen wird.
    private func roundToRealisticWeight(_ weight: Double) -> Double {
        guard weight > 0 else { return 0 }
        let increment = 2.5
        return (weight / increment).rounded() * increment
    }

    /// Sendet die Aufforderung an die Watch, die Herzfrequenz zu messen. Wird
    /// erneut aufgerufen, sobald die Watch erreichbar wird (falls der erste
    /// Versuch zu früh nach dem App-Start kam), aber nur solange noch keine
    /// Herzfrequenz eingetroffen ist und mit einer Obergrenze an Versuchen.
    private func sendStartRequest() {
        guard latestHeartRate == nil, startRequestAttempts < 5 else { return }
        connectivity.sendRemoteWorkoutStart(RemoteWorkoutStartDTO(sessionId: sessionId, activityName: planDay?.name ?? "Training"))
        startRequestAttempts += 1
    }

    private func cancel() {
        connectivity.sendRemoteWorkoutStop(RemoteWorkoutStopDTO(sessionId: sessionId))
        dismiss()
    }

    /// Beendet das Training: stoppt die Herzfrequenzmessung auf der Watch und
    /// wartet kurz auf deren Abschlusswerte (Kalorien, Ø-Herzfrequenz), bevor
    /// die Session gespeichert wird. Trifft die Watch-Antwort nicht rechtzeitig
    /// ein, wird der Durchschnitt aus den bereits empfangenen Live-Werten genutzt.
    @MainActor
    private func finishAsync() async {
        isFinishing = true
        connectivity.sendRemoteWorkoutStop(RemoteWorkoutStopDTO(sessionId: sessionId))
        if remoteAvgHeartRate == nil {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        await finish()
    }

    /// Speichert das Training lokal und - sofern die Watch nicht bereits eine
    /// eigene HKWorkoutSession dafür abgeschlossen hat - zusätzlich als
    /// HKWorkout in HealthKit, damit es auch in der Apple Health/Fitness-App
    /// erscheint (nicht nur Watch-Trainings). Nur abgehakte Sätze zählen für
    /// die gespeicherte Einheit; nicht abgehakte Sätze werden verworfen, aber
    /// ihr zuletzt eingetragenes Gewicht bleibt (via Plan-Eintrag) für das
    /// nächste Training an dieser Stelle erhalten.
    private func finish() async {
        let entries = liveExercises.enumerated().compactMap { index, live -> ExerciseEntry? in
            let completedSets = live.sets.filter(\.isCompleted)
            guard !completedSets.isEmpty else { return nil }
            let sets = completedSets.enumerated().map { setIndex, set in
                SetEntry(reps: set.reps, weightKg: set.weightKg, isWarmup: set.isWarmup, order: setIndex)
            }
            return ExerciseEntry(exerciseId: live.exercise.id, exerciseName: live.exercise.name, order: index, sets: sets)
        }

        updatePlanMemory()

        let fallbackAverageHeartRate = heartRateSamples.isEmpty ? nil : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count)
        let energy = remoteEnergyKcal
        let avgHeartRate = remoteAvgHeartRate ?? fallbackAverageHeartRate

        var healthKitUUID = remoteHealthKitUUID
        if healthKitUUID == nil {
            let workout = await HealthKitManager.shared.saveWorkoutBestEffort(
                activityType: .traditionalStrengthTraining,
                start: startDate,
                end: now,
                totalEnergyBurnedKcal: energy,
                averageHeartRate: avgHeartRate
            )
            healthKitUUID = workout?.uuid.uuidString
        }

        let session = WorkoutSession(
            date: startDate,
            activityName: planDay?.name ?? "Training",
            durationSeconds: now.timeIntervalSince(startDate),
            totalEnergyBurnedKcal: energy,
            averageHeartRate: avgHeartRate,
            source: .iphone,
            healthKitWorkoutUUID: healthKitUUID,
            entries: entries
        )
        modelContext.insert(session)
        // Explizit sichern statt auf den impliziten Autosave-Zeitpunkt zu
        // vertrauen: wird die App kurz nach dem Beenden geschlossen/
        // suspendiert (z.B. direkt nach der Anstrengungs-Bewertung), darf
        // das Training nicht verloren gehen, obwohl es in HealthKit bereits
        // sofort geschrieben wurde.
        try? modelContext.save()
        completedSession = session
    }

    /// Schreibt das zuletzt abgehakte Arbeitsgewicht/-wiederholungen jeder
    /// Übung zurück in ihren Plan-Eintrag, damit exakt dieser Plan-Slot beim
    /// nächsten Mal automatisch damit vorausgefüllt ist - unabhängig davon,
    /// wie dieselbe Übung in einem anderen Plan oder Trainingstag geführt wird.
    private func updatePlanMemory() {
        var didChange = false
        for live in liveExercises {
            guard let planItem = live.planItem else { continue }
            let completedWorkSets = live.sets.filter { $0.isCompleted && !$0.isWarmup }
            guard let lastSet = completedWorkSets.last else { continue }
            planItem.targetWeightKg = lastSet.weightKg
            planItem.targetReps = lastSet.reps
            planItem.pendingWeightIncrease = false
            didChange = true
        }
        // `planItem` gehört zum Plans-Container, nicht zum hier ambient
        // angehängten History-Container (siehe `planItemContext`-Kommentar
        // oben) - deshalb hier explizit auf der richtigen Context-Referenz
        // sichern, statt uns auf den Autosave des (falschen) `modelContext` zu verlassen.
        if didChange {
            try? planItemContext?.save()
        }
    }
}
