import SwiftUI
import SwiftData

struct TrainingPlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    NavigationLink(plan.name) {
                        PlanDetailView(plan: plan)
                    }
                }
                .onDelete(perform: deletePlans)
            }
            .navigationTitle("Trainingspläne")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addPlan()
                    } label: {
                        Label("Neuer Plan", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if plans.isEmpty {
                    ContentUnavailableView("Noch keine Pläne", systemImage: "list.bullet.clipboard", description: Text("Erstelle deinen ersten Trainingsplan."))
                }
            }
        }
    }

    private func addPlan() {
        let plan = TrainingPlan(name: "Neuer Plan", days: [PlanDay(name: "Tag 1", order: 0)])
        modelContext.insert(plan)
        try? modelContext.save()
    }

    private func deletePlans(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(plans[index]) }
        try? modelContext.save()
    }
}
