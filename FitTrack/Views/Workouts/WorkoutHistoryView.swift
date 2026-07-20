import SwiftUI
import SwiftData
import Charts

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @ObservedObject private var strava = StravaManager.shared
    @State private var showingLogSheet = false
    @State private var showingActiveWorkout = false
    @State private var isImporting = false
    @State private var uploadingSessionId: String?
    @State private var stravaErrorMessage: String?

    private var weeklyVolume: [(weekStart: Date, volume: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start ?? session.date
        }
        return grouped
            .map { weekStart, sessionsInWeek in
                let volume = sessionsInWeek.reduce(0.0) { total, session in
                    total + session.entries.reduce(0.0) { $0 + $1.totalVolume }
                }
                return (weekStart: weekStart, volume: volume)
            }
            .filter { $0.volume > 0 }
            .sorted { $0.weekStart < $1.weekStart }
            .suffix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if weeklyVolume.count > 1 {
                    Section("Trainingsvolumen (letzte Wochen)") {
                        Chart(weeklyVolume, id: \.weekStart) { point in
                            BarMark(x: .value("Woche", point.weekStart, unit: .weekOfYear), y: .value("Volumen", point.volume))
                        }
                        .frame(height: 140)
                        .padding(.vertical, 4)
                    }
                }

                ForEach(sessions) { session in
                    NavigationLink {
                        WorkoutDetailView(session: session)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.activityName).font(.body)
                                Spacer()
                                Image(systemName: sourceIcon(for: session))
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 4) {
                                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                if let externalSourceName = session.externalSourceName {
                                    Text("· via \(externalSourceName)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Text(durationText(session.durationSeconds))
                                if let distance = session.distanceMeters {
                                    Text(distanceText(distance))
                                }
                                if let kcal = session.totalEnergyBurnedKcal {
                                    Text("\(Int(kcal)) kcal")
                                }
                                if let hr = session.averageHeartRate {
                                    Text("\(Int(hr)) bpm ⌀")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        // Bewusst auf der linken Seite: ein eigener rechter
                        // .swipeActions-Block hätte den automatischen
                        // Löschen-Button von .onDelete ersetzt statt sich
                        // damit zu kombinieren - Löschen bleibt so unverändert
                        // über die rechte Wischgeste erreichbar.
                        if strava.isConnected {
                            Button {
                                Task { await uploadToStrava(session) }
                            } label: {
                                if uploadingSessionId == session.id {
                                    ProgressView()
                                } else {
                                    Label("Strava", systemImage: "bolt.fill")
                                }
                            }
                            .tint(Color(red: 0.988, green: 0.298, blue: 0.008))
                            .disabled(uploadingSessionId != nil)
                        }
                    }
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("Verlauf")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingActiveWorkout = true
                        } label: {
                            Label("Training jetzt starten", systemImage: "play.fill")
                        }
                        Button {
                            showingLogSheet = true
                        } label: {
                            Label("Workout nachtragen", systemImage: "square.and.pencil")
                        }
                        Button {
                            Task { await importFromHealth() }
                        } label: {
                            Label("Von Apple Health importieren", systemImage: "arrow.down.heart")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Workouts",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Starte ein Training, trainiere mit der Watch oder Apple Fitness/Strava – Cardio-Einheiten erscheinen automatisch hier.")
                    )
                }
            }
            .sheet(isPresented: $showingLogSheet) {
                LogWorkoutView()
            }
            .fullScreenCover(isPresented: $showingActiveWorkout) {
                ActiveWorkoutView(planDay: nil)
            }
            .task {
                await importFromHealth()
            }
            .refreshable {
                await importFromHealth()
            }
            .alert("Strava-Upload fehlgeschlagen", isPresented: Binding(
                get: { stravaErrorMessage != nil },
                set: { if !$0 { stravaErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(stravaErrorMessage ?? "")
            }
        }
    }

    private func uploadToStrava(_ session: WorkoutSession) async {
        uploadingSessionId = session.id
        defer { uploadingSessionId = nil }

        do {
            try await strava.uploadActivity(for: session)
        } catch {
            stravaErrorMessage = error.localizedDescription
        }
    }

    private func sourceIcon(for session: WorkoutSession) -> String {
        switch session.source {
        case .watch: return "applewatch"
        case .iphone: return "iphone"
        case .health: return "arrow.down.heart"
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes) min"
    }

    private func distanceText(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    private func importFromHealth() async {
        guard !isImporting else { return }
        isImporting = true
        await HealthKitImportService.importNewWorkouts(existingSessions: sessions, modelContext: modelContext)
        isImporting = false
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            if let uuid = session.healthKitWorkoutUUID {
                DismissedHealthKitWorkouts.markDismissed(uuid)
            }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}
