import SwiftUI
import SwiftData
import FitTrackShared

struct PlanDetailView: View {
    @Bindable var plan: TrainingPlan
    @Environment(\.modelContext) private var modelContext
    @State private var showingShareSheet = false

    var body: some View {
        List {
            Section {
                TextField("Name", text: $plan.name)
                TextField("Notizen", text: $plan.notes, axis: .vertical)
            }

            Section("Trainingstage") {
                ForEach(plan.dayList.sorted(by: { $0.order < $1.order })) { day in
                    NavigationLink {
                        PlanDayDetailView(day: day, planName: plan.name)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(day.name)
                            Text("\(day.itemList.count) Übungen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteDays)

                Button {
                    addDay()
                } label: {
                    Label("Tag hinzufügen", systemImage: "plus")
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            SharePlanView(plan: plan)
        }
    }

    private func addDay() {
        let nextOrder = (plan.dayList.map(\.order).max() ?? -1) + 1
        plan.dayList.append(PlanDay(name: "Tag \(nextOrder + 1)", order: nextOrder))
        // Explizit sichern statt auf den impliziten Autosave-Zeitpunkt zu
        // vertrauen - sonst kann ein neu hinzugefügter Tag verloren gehen,
        // wenn die App vor dem nächsten Autosave geschlossen wird.
        try? modelContext.save()
    }

    private func deleteDays(at offsets: IndexSet) {
        let sorted = plan.dayList.sorted(by: { $0.order < $1.order })
        for index in offsets {
            if let idx = plan.dayList.firstIndex(where: { $0.persistentModelID == sorted[index].persistentModelID }) {
                modelContext.delete(plan.dayList[idx])
                plan.dayList.remove(at: idx)
            }
        }
        try? modelContext.save()
    }
}
