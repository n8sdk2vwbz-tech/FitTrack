import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Group {
                        if let readiness = viewModel.readiness {
                            ReadinessRingView(readiness: readiness)
                            ReadinessBreakdownView(readiness: readiness)
                        } else if viewModel.isLoading {
                            ProgressView("Lade Erholungsdaten…")
                                .padding(.top, 40)
                        } else {
                            Text("Noch keine Daten verfügbar")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }

                    CardioReadinessCard(status: viewModel.muscleStatuses[.cardio], readiness: viewModel.readiness)

                    MuscleHeatmapView(statuses: viewModel.muscleStatuses, readiness: viewModel.readiness)
                }
                .padding()
            }
            .navigationTitle("Übersicht")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                StravaSettingsView()
            }
            .task { await viewModel.refresh(sessions: sessions, modelContext: modelContext) }
            .refreshable { await viewModel.refresh(sessions: sessions, modelContext: modelContext) }
            .onChange(of: sessions.count) {
                Task { await viewModel.refresh(sessions: sessions, modelContext: modelContext) }
            }
            .onAppear {
                // Deckt auch den Fall ab, dass sich ein bestehendes Training
                // geändert hat (z.B. Anstrengung nachträglich im Verlauf
                // bewertet) - `sessions.count` bleibt dabei gleich, würde also
                // sonst keinen Refresh auslösen.
                Task { await viewModel.refresh(sessions: sessions, modelContext: modelContext) }
            }
        }
    }
}
