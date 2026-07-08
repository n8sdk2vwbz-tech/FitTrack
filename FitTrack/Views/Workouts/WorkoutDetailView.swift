import SwiftUI

struct WorkoutDetailView: View {
    @Bindable var session: WorkoutSession

    var body: some View {
        List {
            Section {
                LabeledContent("Datum", value: session.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Dauer", value: "\(Int(session.durationSeconds / 60)) min")
                if let distance = session.distanceMeters {
                    LabeledContent("Distanz", value: String(format: "%.2f km", distance / 1000))
                }
                if let kcal = session.totalEnergyBurnedKcal {
                    LabeledContent("Kalorien", value: "\(Int(kcal)) kcal")
                }
                if let hr = session.averageHeartRate {
                    LabeledContent("Ø Herzfrequenz", value: "\(Int(hr)) bpm")
                }
                LabeledContent("Quelle", value: sourceText)
            }

            Section {
                EffortRatingBars(rating: $session.perceivedExertion)
                    .frame(height: 70)
                    .padding(.vertical, 4)
                if let perceivedExertion = session.perceivedExertion {
                    Text("\(perceivedExertion)/10 · \(effortLabel(perceivedExertion))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Anstrengung")
            } footer: {
                Text("Fließt in die Trainingslast und deinen Bereitschafts-Score ein.")
            }

            ForEach(session.entries.sorted(by: { $0.order < $1.order })) { entry in
                Section(entry.exerciseName) {
                    ForEach(Array(entry.sets.sorted(by: { $0.order < $1.order }).enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("Satz \(index + 1)")
                            Spacer()
                            Text("\(set.reps) x \(set.weightKg, specifier: "%.1f") kg")
                            if set.isWarmup {
                                Text("Aufwärmen").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.activityName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sourceText: String {
        switch session.source {
        case .watch: return "Apple Watch"
        case .iphone: return "iPhone"
        case .health: return session.externalSourceName.map { "Health (\($0))" } ?? "Apple Health"
        }
    }
}
