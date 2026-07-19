import SwiftUI
import SwiftData
import FitTrackShared

/// Bestätigungs-Dialog nach dem Öffnen eines geteilten Plan-Links/QR-Codes
/// (siehe `PlanSharePayload`/`RootView.onOpenURL`) - legt den Plan erst nach
/// ausdrücklicher Bestätigung im Plans-Container an, nie automatisch beim
/// bloßen Öffnen des Links.
struct ImportPlanView: View {
    let sharedPlan: SharedPlanDTO
    @Environment(\.dismiss) private var dismiss
    @State private var didImport = false

    private var totalExercises: Int {
        sharedPlan.days.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(sharedPlan.name).font(.headline)
                    if !sharedPlan.notes.isEmpty {
                        Text(sharedPlan.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(sharedPlan.days.count) Trainingstage · \(totalExercises) Übungen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Trainingstage") {
                    ForEach(Array(sharedPlan.days.enumerated()), id: \.offset) { _, day in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name)
                            Text("\(day.items.count) Übungen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("Nur Übungen, Sätze/Wiederholungen und Notizen werden übernommen - Gewichte startest du selbst bei 0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plan importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { importPlan() }
                        .disabled(didImport)
                }
            }
            .overlay {
                if didImport {
                    ContentUnavailableView("Plan importiert", systemImage: "checkmark.circle.fill", description: Text("Zu finden im Tab \"Pläne\"."))
                        .background(.background)
                }
            }
        }
    }

    private func importPlan() {
        let context = ModelContext(AppContainers.plans)
        context.insert(sharedPlan.makePlan())
        try? context.save()
        didImport = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}
