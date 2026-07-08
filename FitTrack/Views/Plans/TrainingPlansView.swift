import SwiftUI
import SwiftData

struct TrainingPlansView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingPlan.createdAt, order: .reverse) private var plans: [TrainingPlan]
    @State private var showingGenerator = false
    @State private var createdPlan: TrainingPlan?

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
                    Menu {
                        Button {
                            addPlan()
                        } label: {
                            Label("Leerer Plan", systemImage: "plus")
                        }
                        Button {
                            showingGenerator = true
                        } label: {
                            Label("Plan erstellen lassen", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if plans.isEmpty {
                    ContentUnavailableView("Noch keine Pläne", systemImage: "list.bullet.clipboard", description: Text("Erstelle deinen ersten Trainingsplan."))
                }
            }
            .sheet(isPresented: $showingGenerator) {
                GeneratePlanView { plan in
                    createdPlan = plan
                }
            }
            .navigationDestination(item: $createdPlan) { plan in
                PlanDetailView(plan: plan)
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
