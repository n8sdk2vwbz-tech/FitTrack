import SwiftUI
import SwiftData
import UserNotifications
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
    @ObservedObject private var liveActivityRelay = LiveActivityActionRelay.shared
    /// Siehe `StravaSettingsView` - auf welches Plattenschritt-Raster
    /// Aufwärmgewichte gerundet werden.
    @AppStorage("warmupWeightIncrementKg") private var warmupWeightIncrementKg: Double = 2.5
    /// Siehe `StravaSettingsView` - ob der HF-basierte Satzpausen-Timer aktiv ist.
    @AppStorage("restTimerEnabled") private var restTimerEnabled = false

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
    @State private var isRestTimerActive = false
    @State private var restElapsedSeconds: Double = 0

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
                    if isRestTimerActive {
                        HStack {
                            Label("Pause", systemImage: "heart.text.square")
                            Spacer()
                            Text("\(Int(restElapsedSeconds))s")
                                .monospacedDigit()
                                .foregroundStyle(.orange)
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
                        if let planItem = live.planItem, planItem.targetRepsMax != nil {
                            Text("Ziel: \(planItem.targetRepsDisplay) Wdh.")
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
                        if live.sets.contains(where: { $0.isWarmup }) {
                            Button {
                                recalculateWarmups(for: $live)
                            } label: {
                                Label("Aufwärmsätze anhand aktuellem Gewicht aktualisieren", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(Array($live.sets.enumerated()), id: \.element.id) { index, $set in
                            HStack(spacing: 6) {
                                Button {
                                    set.isCompleted.toggle()
                                    if set.isCompleted {
                                        // Watch misst die Herzfrequenz - sie
                                        // (nicht das iPhone) entscheidet anhand
                                        // der synchronisierten Einstellung, ob
                                        // die Satzpausen-Überwachung startet.
                                        connectivity.sendRestTimerTrigger(RestTimerTriggerDTO(sessionId: sessionId))
                                    }
                                    refreshLiveActivity()
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
                LiveActivityManager.shared.start(sessionId: sessionId, state: currentLiveActivityState())
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
                refreshLiveActivity()
            }
            .onChange(of: connectivity.remoteWorkoutResult) { _, result in
                guard let result, result.sessionId == sessionId else { return }
                remoteEnergyKcal = result.totalEnergyBurnedKcal
                remoteAvgHeartRate = result.averageHeartRate
                remoteHealthKitUUID = result.healthKitWorkoutUUID
            }
            .onChange(of: connectivity.restTimerStatus) { _, status in
                guard let status, status.sessionId == sessionId else { return }
                let wasActive = isRestTimerActive
                isRestTimerActive = status.isActive
                restElapsedSeconds = status.elapsedSeconds
                if wasActive, !status.isActive {
                    notifyRestComplete()
                }
                refreshLiveActivity()
            }
            .onChange(of: connectivity.remoteSetCompleted) { _, dto in
                guard let dto, dto.sessionId == sessionId else { return }
                completeNextPendingSet()
                refreshLiveActivity()
            }
            .onChange(of: liveActivityRelay.completeSetRequested) { _, event in
                guard event != nil else { return }
                completeNextPendingSet()
                // Anders als beim Watch-Button (der die HF-Überwachung direkt
                // auf der Watch selbst startet) läuft dieser Intent auf dem
                // iPhone - ohne diesen Trigger würde die Watch nie erfahren,
                // dass gerade ein Satz abgehakt wurde, und die Pause nie starten.
                connectivity.sendRestTimerTrigger(RestTimerTriggerDTO(sessionId: sessionId))
                refreshLiveActivity()
            }
            .onChange(of: liveActivityRelay.repsAdjustment) { _, event in
                guard let event else { return }
                adjustNextPendingSetReps(by: event.delta)
                refreshLiveActivity()
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

    /// Gewichts-Anteil vom Arbeitsgewicht und Wiederholungen je Aufwärmsatz,
    /// je nach Gesamtzahl der Aufwärmsätze - angelehnt an eine verbreitete
    /// evidenzbasierte Aufwärm-Tabelle ("Exercise-Specific Warm-Up"). Deren
    /// Wiederholungs-Spannen (z.B. "6-10") sind hier bewusst auf den oberen
    /// Wert gerundet. Für 5 Aufwärmsätze existiert dort keine Vorgabe - eigene
    /// Erweiterung des Musters (ein zusätzlicher Zwischenschritt) statt einer
    /// Vermutung ins Blaue.
    private static let warmupTemplates: [Int: [(percent: Double, reps: Int)]] = [
        1: [(0.60, 10)],
        2: [(0.50, 10), (0.70, 6)],
        3: [(0.45, 10), (0.65, 6), (0.85, 4)],
        4: [(0.45, 10), (0.60, 6), (0.75, 5), (0.85, 4)],
        5: [(0.40, 10), (0.55, 8), (0.65, 6), (0.78, 4), (0.88, 3)]
    ]

    private func warmupSets(workWeight: Double, workReps: Int, count: Int) -> [(weight: Double, reps: Int)] {
        guard count > 0 else { return [] }
        guard workWeight > 0 else { return Array(repeating: (0, workReps), count: count) }

        let template = Self.warmupTemplates[count] ?? Self.warmupTemplates[4] ?? [(0.60, 10)]
        return template.map { entry in
            (roundUpToRealisticWeight(workWeight * entry.percent), entry.reps)
        }
    }

    /// Rundet nach oben (nie ab) auf das Plattenschritt-Raster - bei
    /// prozentual berechneten Aufwärmgewichten lieber etwas schwerer als zu
    /// leicht, damit der Aufwärmeffekt nicht zu gering ausfällt.
    private func roundUpToRealisticWeight(_ weight: Double) -> Double {
        guard weight > 0 else { return 0 }
        let increment = warmupWeightIncrementKg
        return (weight / increment).rounded(.up) * increment
    }

    /// Berechnet die Aufwärmsätze einer Übung anhand des aktuell im ersten
    /// Arbeitssatz eingetragenen Gewichts neu und ersetzt die bisherigen
    /// Aufwärmsätze damit - nötig, weil `setupFromPlanIfNeeded` sie nur
    /// einmalig beim Trainingsstart aus dem gespeicherten Gewicht berechnet.
    /// War das noch nicht gesetzt (z.B. bei einer neuen Übung ohne Historie),
    /// bleiben sie sonst dauerhaft bei 0 kg/gleicher Wiederholungszahl stehen,
    /// auch nachdem das echte Gewicht für heute eingetragen wurde.
    private func recalculateWarmups(for live: Binding<LiveExercise>) {
        let workSets = live.wrappedValue.sets.filter { !$0.isWarmup }
        let workWeight = workSets.first?.weightKg ?? 0
        let workReps = workSets.first?.reps ?? live.wrappedValue.targetReps
        let warmupCount = live.wrappedValue.sets.filter(\.isWarmup).count
        let newWarmups = warmupSets(workWeight: workWeight, workReps: workReps, count: warmupCount).map {
            LiveSet(reps: $0.reps, weightKg: $0.weight, isWarmup: true)
        }
        live.wrappedValue.sets.removeAll { $0.isWarmup }
        live.wrappedValue.sets.insert(contentsOf: newWarmups, at: 0)
    }

    /// Rundet auf ein in Fitnessstudios übliches Plattenschritt-Raster (2,5
    /// oder 5 kg, einstellbar - nicht jedes Studio hat 2,5-kg-Scheiben),
    /// damit z.B. nie "18,836 kg" statt "17,5 kg" vorgeschlagen wird.
    private func roundToRealisticWeight(_ weight: Double) -> Double {
        guard weight > 0 else { return 0 }
        let increment = warmupWeightIncrementKg
        return (weight / increment).rounded() * increment
    }

    /// Sendet die Aufforderung an die Watch, die Herzfrequenz zu messen. Wird
    /// erneut aufgerufen, sobald die Watch erreichbar wird (falls der erste
    /// Versuch zu früh nach dem App-Start kam), aber nur solange noch keine
    /// Herzfrequenz eingetroffen ist und mit einer Obergrenze an Versuchen.
    /// Zusätzlich zur Watch-Vibration eine kurze Mitteilung am iPhone, falls
    /// der Nutzer gerade dort statt auf die Uhr schaut - die App muss dafür
    /// nicht im Vordergrund sein (Berechtigung wird still im Hintergrund
    /// abgefragt, siehe `RootView`).
    private func notifyRestComplete() {
        let content = UNMutableNotificationContent()
        content.title = "Bereit für den nächsten Satz"
        content.body = "Deine Herzfrequenz hat sich erholt."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "rest-timer-\(sessionId)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Markiert den nächsten noch offenen Satz als erledigt - ausgelöst durch
    /// den "Satz erledigt"-Button direkt auf der Watch (siehe
    /// `WorkoutManager.completeSetRemotely`/`RemoteSetCompletedDTO`) oder in
    /// der Live Activity (siehe `CompleteSetLiveActivityIntent`), da beide bei
    /// einem ferngesteuerten Training selbst keine Übungen/Sätze kennen.
    /// Dieselbe Reihenfolge (Übung für Übung, darin Satz für Satz) wie beim
    /// manuellen Abhaken hier in der Liste. Löst bewusst KEINEN erneuten
    /// `sendRestTimerTrigger` aus - die Watch hat ihre HF-Überwachung dafür
    /// bereits selbst gestartet.
    private func completeNextPendingSet() {
        for exerciseIndex in liveExercises.indices {
            if let setIndex = liveExercises[exerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) {
                liveExercises[exerciseIndex].sets[setIndex].isCompleted = true
                return
            }
        }
    }

    /// Passt die Wiederholungen des nächsten noch offenen Satzes an - vom
    /// Stepper in der Live Activity ausgelöst (siehe `AdjustNextSetRepsIntent`).
    /// Nie unter 1 Wdh., damit der Stepper nicht auf 0 oder negativ laufen kann.
    private func adjustNextPendingSetReps(by delta: Int) {
        for exerciseIndex in liveExercises.indices {
            if let setIndex = liveExercises[exerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) {
                let current = liveExercises[exerciseIndex].sets[setIndex].reps
                liveExercises[exerciseIndex].sets[setIndex].reps = max(1, current + delta)
                return
            }
        }
    }

    /// Info zum nächsten noch offenen Satz (Übung für Übung, darin Satz für
    /// Satz) - Grundlage sowohl für `completeNextPendingSet`/
    /// `adjustNextPendingSetReps` als auch für die Live-Activity-Anzeige.
    private var nextPendingSetInfo: (exerciseName: String, reps: Int, weightKg: Double?, isWarmup: Bool)? {
        for live in liveExercises {
            if let set = live.sets.first(where: { !$0.isCompleted }) {
                return (live.exercise.name, set.reps, set.weightKg > 0 ? set.weightKg : nil, set.isWarmup)
            }
        }
        return nil
    }

    private func currentLiveActivityState() -> RestTimerActivityAttributes.ContentState {
        let next = nextPendingSetInfo
        return RestTimerActivityAttributes.ContentState(
            heartRate: latestHeartRate ?? 0,
            isResting: isRestTimerActive,
            restElapsedSeconds: Int(restElapsedSeconds),
            nextExerciseName: next?.exerciseName ?? "Fertig",
            nextSetReps: next?.reps ?? 0,
            nextSetWeightKg: next?.weightKg,
            nextSetIsWarmup: next?.isWarmup ?? false,
            hasNextSet: next != nil
        )
    }

    private func refreshLiveActivity() {
        LiveActivityManager.shared.update(currentLiveActivityState())
    }

    private func sendStartRequest() {
        guard latestHeartRate == nil, startRequestAttempts < 5 else { return }
        print("🔧 RestTimerDebug: sendStartRequest Versuch #\(startRequestAttempts + 1), restTimerEnabled=\(restTimerEnabled), reachable=\(connectivity.isCounterpartReachable)")
        connectivity.sendRemoteWorkoutStart(RemoteWorkoutStartDTO(sessionId: sessionId, activityName: planDay?.name ?? "Training", restTimerEnabled: restTimerEnabled))
        startRequestAttempts += 1
    }

    private func cancel() {
        // discard: true - anders als beim regulären Beenden soll die Watch
        // ihre HKWorkoutSession verwerfen statt sie zu speichern, sonst
        // landet trotz Abbruch ein (sehr kurzes) Workout in Health und wird
        // von dort automatisch wieder als eigene Einheit importiert.
        connectivity.sendRemoteWorkoutStop(RemoteWorkoutStopDTO(sessionId: sessionId, discard: true))
        LiveActivityManager.shared.end()
        dismiss()
    }

    /// Beendet das Training: stoppt die Herzfrequenzmessung auf der Watch und
    /// wartet auf deren Abschlusswerte (u.a. die HealthKit-UUID ihrer eigenen
    /// Workout-Session), bevor die Session gespeichert wird. Ohne ausreichend
    /// Wartezeit würde `finish()` sonst selbst ein zweites HKWorkout anlegen,
    /// weil `builder.finishWorkout()` auf der Watch plus der WatchConnectivity-
    /// Rückweg zuverlässig länger als eine kurze feste Wartezeit dauern kann -
    /// das führte zu doppelten Einträgen in Apple Health/Fitness für dieselbe
    /// Einheit (einer davon ohne Kalorien, weil er vor Eintreffen der
    /// vollständigen Watch-Werte gespeichert wurde). Pollt daher in kurzen
    /// Abständen bis zu einer großzügigeren Obergrenze, statt einmalig kurz zu
    /// warten, und bricht sofort ab, sobald die Watch-Antwort eingetroffen ist.
    @MainActor
    private func finishAsync() async {
        isFinishing = true
        connectivity.sendRemoteWorkoutStop(RemoteWorkoutStopDTO(sessionId: sessionId, discard: false))
        LiveActivityManager.shared.end()
        let maxWaitNanoseconds: UInt64 = 6_000_000_000
        let pollIntervalNanoseconds: UInt64 = 300_000_000
        var waited: UInt64 = 0
        while remoteHealthKitUUID == nil, remoteAvgHeartRate == nil, waited < maxWaitNanoseconds {
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            waited += pollIntervalNanoseconds
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
        Task { await StravaManager.shared.autoUploadIfNeeded(session: session) }
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
