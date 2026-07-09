import SwiftUI
import FitTrackShared

struct ReadinessRingView: View {
    let readiness: ReadinessResult
    @State private var showingExplanation = false

    var body: some View {
        VStack(spacing: 12) {
            Button {
                showingExplanation = true
            } label: {
                ZStack {
                    Circle()
                        .stroke(readiness.category.color.opacity(0.15), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: CGFloat(readiness.score) / 100.0)
                        .stroke(readiness.category.color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: readiness.score)

                    VStack(spacing: 2) {
                        Text("\(readiness.score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        HStack(spacing: 3) {
                            Text("Bereitschaft")
                                .font(.caption)
                            Image(systemName: "info.circle")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
            }
            .buttonStyle(.plain)

            Text(readiness.category.displayName)
                .font(.headline)
                .foregroundStyle(readiness.category.color)

            Text(readiness.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .sheet(isPresented: $showingExplanation) {
            ReadinessExplanationView(readiness: readiness)
        }
    }
}

struct ReadinessBreakdownView: View {
    let readiness: ReadinessResult

    var body: some View {
        VStack(spacing: 8) {
            breakdownRow(title: "Schlaf", score: readiness.sleepScore, icon: "bed.double.fill")
            breakdownRow(title: "HRV", score: readiness.hrvScore, icon: "waveform.path.ecg")
            breakdownRow(title: "Ruhepuls", score: readiness.rhrScore, icon: "heart.fill")
            breakdownRow(title: "Trainingslast", score: readiness.trainingLoadScore, icon: "figure.strengthtraining.traditional")
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func breakdownRow(title: String, score: Int?, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let score {
                Text("\(score)")
                    .fontWeight(.semibold)
            } else {
                Text("–")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

/// Erklärt, wie sich der Bereitschafts-Score zusammensetzt und mit welchen
/// Werten er sich verbessert - aufgerufen durch Antippen des Scores im Dashboard.
private struct ReadinessExplanationView: View {
    let readiness: ReadinessResult
    @Environment(\.dismiss) private var dismiss

    private struct Component {
        let title: String
        let icon: String
        let weight: String
        let currentScore: Int?
        /// Rohwerte hinter dem Score (z.B. "6.8 Std." oder "45 ms · Ø 42 ms"),
        /// damit nachvollziehbar ist, warum ein Score bei 100 gedeckelt ist -
        /// die Scores selbst zeigen nicht, wie weit man über dem eigenen
        /// Basiswert liegt (siehe `ReadinessResult`-Dokumentation).
        let rawValue: String?
        let explanation: String
        let improvement: String
    }

    private var components: [Component] {
        [
            Component(
                title: "Schlaf",
                icon: "bed.double.fill",
                weight: "30 %",
                currentScore: readiness.sleepScore,
                rawValue: readiness.sleepHours.map { String(format: "%.1f Std.", $0) },
                explanation: "Schlafdauer der letzten Nacht im Verhältnis zu 8 Stunden, multipliziert mit der Schlafeffizienz (Anteil tatsächlicher Schlafzeit an der Zeit im Bett).",
                improvement: "Verbessert sich durch mehr durchgehenden, ungestörten Schlaf nahe 8 Stunden."
            ),
            Component(
                title: "HRV",
                icon: "waveform.path.ecg",
                weight: "25 %",
                currentScore: readiness.hrvScore,
                rawValue: rawValuePair(current: readiness.hrvMs, baseline: readiness.hrvBaselineMs, unit: "ms"),
                explanation: "Deine Herzfrequenzvariabilität der letzten Nacht im Verhältnis zu deinem eigenen 14-Tage-Durchschnitt.",
                improvement: "Verbessert sich, wenn deine HRV höher ist als dein persönlicher Durchschnitt – ein Zeichen für gute Erholung und niedrigen Stress. Der Score kappt bei Erreichen des eigenen Durchschnitts bei 100 - auch deutlich darüber liegende Werte zeigen also denselben Score."
            ),
            Component(
                title: "Ruhepuls",
                icon: "heart.fill",
                weight: "15 %",
                currentScore: readiness.rhrScore,
                rawValue: rawValuePair(current: readiness.restingHeartRate, baseline: readiness.restingHeartRateBaseline, unit: "bpm"),
                explanation: "Dein aktueller Ruhepuls im Verhältnis zu deinem eigenen 14-Tage-Durchschnitt.",
                improvement: "Verbessert sich, wenn dein Ruhepuls niedriger ist als gewohnt. Ein erhöhter Ruhepuls deutet oft auf Stress, Krankheit oder unvollständige Erholung hin. Der Score kappt bei Erreichen des eigenen Durchschnitts bei 100 - auch deutlich niedrigere Werte zeigen also denselben Score."
            ),
            Component(
                title: "Trainingslast",
                icon: "figure.strengthtraining.traditional",
                weight: "30-55 %",
                currentScore: readiness.trainingLoadScore,
                rawValue: nil,
                explanation: "In den ersten 10 Trainingseinheiten: Volumen und wahrgenommene Anstrengung (RPE und/oder Trainings-Herzfrequenz) der letzten Einheit allein, verglichen mit einem allgemeinen Richtwert - klingt über ca. 4 Tage auf neutral ab, falls seitdem keine neue Einheit protokolliert wurde. Die Herzfrequenz wird dabei nach Möglichkeit relativ zu deiner geschätzten HFmax bewertet (aus deinem in Health hinterlegten Geburtsdatum), sonst gegen einen festen Richtwert. Ab der 10. Einheit kommt zusätzlich die langfristige Belastung (Verhältnis aus kurz- zu langfristiger Trainingslast, ACWR) über die letzten Wochen dazu. Das Gewicht steigt zusätzlich auf bis zu 55 %, je frischer die letzte Einheit ist: Schlaf/HRV/Ruhepuls spiegeln nur deinen Zustand vor dieser Einheit wider und können ein gerade erst absolviertes Training noch nicht erfassen.",
                improvement: "Verbessert sich durch ein als leicht empfundenes Training mit moderatem Volumen, oder einfach durch verstreichende Zeit seit der letzten Einheit – bzw. ab der 10. Einheit zusätzlich, wenn die Belastung der letzten Tage nicht deutlich über deinem längerfristigen Durchschnitt liegt."
            )
        ]
    }

    private func rawValuePair(current: Double?, baseline: Double?, unit: String) -> String? {
        guard let current else { return nil }
        guard let baseline else { return String(format: "%.0f %@", current, unit) }
        return String(format: "%.0f %@ · Ø %.0f %@", current, unit, baseline, unit)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(readiness.score)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(readiness.category.color)
                        VStack(alignment: .leading) {
                            Text(readiness.category.displayName)
                                .font(.headline)
                            Text("Gewichteter Mittelwert aus den vier Bausteinen unten. Fehlt eine Datenquelle (z.B. keine Apple Watch getragen), wird nur aus den verfügbaren Bausteinen berechnet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(components, id: \.title) { component in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if let rawValue = component.rawValue {
                                Text(rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            Text(component.explanation)
                                .font(.subheadline)
                            Text(component.improvement)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } header: {
                        HStack {
                            Label(component.title, systemImage: component.icon)
                            Spacer()
                            Text("Gewichtung \(component.weight)")
                            if let score = component.currentScore {
                                Text("· aktuell \(score)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wie wird die Bereitschaft berechnet?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
